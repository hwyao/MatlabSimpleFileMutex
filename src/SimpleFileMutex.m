classdef SimpleFileMutex < handle
    % SimpleFileMutex - A simple file-based mutex implementation for MATLAB
    
    properties (SetAccess = private)
        % Path to the lock file
        lockFilePath        

        % Path to the file being protected
        targetFilePath
        
        % Boolean flag indicating if mutex is currently locked
        isLocked

        % Unique identifier for this process instance       
        processId
        
        % Maximum number of retries for unexpected errors
        unexpectedRetryMax
        
        % Counter for unexpected retries
        unexpectedRetryCount = 0; 

        % Pause time between lock attempts in seconds
        pauseTimeByLocking  

        % Java RandomAccessFile object for the lock file
        lockFile
        
        % Java FileChannel object
        lockChannel

        % Java FileLock object
        fileLock            
    end
    
    methods
        function obj = SimpleFileMutex(filePath, varargin)
            % SimpleFileMutex Constructor
            % 
            % Creates a new file-based mutex instance for protecting access to a specified file.
            % The constructor validates input parameters and initializes the mutex state.
            %
            % Syntax:
            %   obj = SimpleFileMutex(filePath)
            %   obj = SimpleFileMutex(filePath, 'UnexpectedRetryMax', value)
            %   obj = SimpleFileMutex(filePath, 'PauseTimeByLocking', value)
            %
            % Input Arguments:
            %   filePath - String or char array specifying the path to an existing file 
            %              that needs to be protected by the mutex. This parameter is required
            %              and the file must exist.
            %
            % Name-Value Arguments:
            %   'UnexpectedRetryMax' - Positive integer specifying the maximum number of 
            %                          retries when unexpected errors occur during lock 
            %                          acquisition. Default is 20.
            %   'PauseTimeByLocking' - Positive number specifying the pause time in seconds
            %                          between lock acquisition attempts. Default is 0.1.
            %
            % Output Arguments:
            %   obj - SimpleFileMutex object instance
            %
            % Examples:
            %   % Basic usage
            %   mutex = SimpleFileMutex('myfile.txt');
            %
            %   % With custom retry limit and pause time
            %   mutex = SimpleFileMutex('myfile.txt', 'UnexpectedRetryMax', 50, 'PauseTimeByLocking', 0.05);

            % validate required filePath not empty, is a string or char array, and file exists
            if nargin < 1 || isempty(filePath)
                error('SimpleFileMutex:InvalidInput', 'File path must be specified');
            end
            
            if ~(ischar(filePath) || isstring(filePath))
                error('SimpleFileMutex:InvalidInput', 'File path must be a string or char array');
            end
            
            filePathChar = char(filePath);
            if ~isfile(filePathChar)
                error('SimpleFileMutex:FileNotFound', 'The specified file does not exist: %s', filePathChar);
            end

            % Create input parser for optional arguments
            p = inputParser;
            addParameter(p, 'UnexpectedRetryMax', 20, @(x) isnumeric(x) && isscalar(x) && x >= 0 && floor(x) == x);
            addParameter(p, 'PauseTimeByLocking', 0.1, @(x) isnumeric(x) && isscalar(x) && x > 0);
            parse(p, varargin{:});
            
            % Initialize properties
            obj.targetFilePath = filePathChar;
            obj.isLocked = false;
            obj.unexpectedRetryMax = p.Results.UnexpectedRetryMax;
            obj.pauseTimeByLocking = p.Results.PauseTimeByLocking;
            obj.processId = sprintf('MATLAB_%d', feature('getpid'));
            
            % Create lock file path
            [pathStr, name, ext] = fileparts(obj.targetFilePath);
            obj.lockFilePath = fullfile(pathStr, [name ext '.lock']);
            
            % Initialize Java objects as empty
            obj.lockFile = [];
            obj.lockChannel = [];
            obj.fileLock = [];
        end

        function delete(obj)
            % delete - Destructor to ensure mutex lock is properly released
            %
            % This method is automatically called when the SimpleFileMutex object is 
            % destroyed or goes out of scope. It ensures that any held lock is properly 
            % released to prevent deadlocks or resource leaks.
            %
            % Syntax:
            %   delete(obj)
            %   clear obj  % Triggers destructor
            %
            % Input Arguments:
            %   obj - SimpleFileMutex object instance
            %
            % Notes:
            %   - This method is called automatically by MATLAB's garbage collector
            %   - Manual calling is generally not necessary
            %   - If the mutex is locked when destroyed, unlock() will be called automatically
            if obj.isLocked
                obj.unlock();
            end
        end
        
        function lock(obj)
            % lock - Acquire the mutex lock using Java FileLock
            %
            % Attempts to acquire an exclusive lock using Java's FileLock mechanism. 
            % This provides true cross-process mutual exclusion that works across 
            % different MATLAB instances and other processes.
            %
            % Syntax:
            %   lock(obj)
            %
            % Input Arguments:
            %   obj - SimpleFileMutex object instance
            %
            % Behavior:
            %   - Uses Java RandomAccessFile and FileChannel for locking
            %   - Creates a .lock file alongside the target file
            %   - Blocks until lock is acquired or maximum retries exceeded
            %   - Handles unexpected errors with configurable retry mechanism
            %
            % Exceptions:
            %   SimpleFileMutex:AlreadyLocked - If this instance already holds the lock
            %   SimpleFileMutex:MaxRetriesExceeded - If maximum retry limit is reached
            %   SimpleFileMutex:LockFailed - If unexpected errors occur during acquisition
            %
            % Examples:
            %   mutex = SimpleFileMutex('data.mat');
            %   mutex.lock();  % Blocks until lock is acquired
            %   % ... perform file operations ...
            %   mutex.unlock();
            
            if obj.isLocked
                warning('SimpleFileMutex:AlreadyLocked', 'Mutex is already locked by this instance');
                return;
            end

            obj.unexpectedRetryCount = 0;
            
            while true
                try
                    % Create or open the lock file using Java
                    obj.lockFile = java.io.RandomAccessFile(obj.lockFilePath, 'rw');
                    obj.lockChannel = obj.lockFile.getChannel();
                    
                    % Try to acquire exclusive lock (non-blocking first attempt)
                    obj.fileLock = obj.lockChannel.tryLock();
                    
                    if ~isempty(obj.fileLock)
                        % Successfully acquired lock
                        % Write process information to the lock file
                        lockContent = sprintf('ProcessID: %s\nTimestamp: %s\n', ...
                                            obj.processId, string(datetime("now")));
                        obj.lockFile.seek(0);
                        obj.lockFile.writeBytes(lockContent);
                        obj.lockFile.setLength(length(lockContent));
                        
                        obj.isLocked = true;
                        return;
                    else
                        % Lock not available, clean up and retry
                        obj.lockChannel.close();
                        obj.lockFile.close();
                        obj.lockChannel = [];
                        obj.lockFile = [];
                        
                        pause(obj.pauseTimeByLocking);
                        continue;
                    end
                    
                catch ME
                    % Clean up Java objects on error
                    obj.cleanupJavaObjects();
                    
                    obj.unexpectedRetryCount = obj.unexpectedRetryCount + 1;
                    
                    if obj.unexpectedRetryCount > obj.unexpectedRetryMax
                        error('SimpleFileMutex:MaxRetriesExceeded', ...
                              'Maximum number of retries (%d) exceeded. Last error: %s', ...
                              obj.unexpectedRetryMax, ME.message);
                    end
                    
                    pause(obj.pauseTimeByLocking);
                    warning('SimpleFileMutex:LockFailed', ...
                            'Unexpected error while trying to acquire lock (retry %d/%d): %s. by PID %s. Will retry.', ... 
                            obj.unexpectedRetryCount, obj.unexpectedRetryMax, ME.message, obj.processId);
                    continue;
                end
            end
        end
        
        function unlock(obj)
            % unlock - Release the mutex lock using Java FileLock
            %
            % Releases the mutex lock by releasing the Java FileLock and closing 
            % associated file handles. This method should be called after completing 
            % operations on the protected file to allow other processes to acquire the lock.
            %
            % Syntax:
            %   unlock(obj)
            %
            % Input Arguments:
            %   obj - SimpleFileMutex object instance
            %
            % Behavior:
            %   - Releases the Java FileLock object
            %   - Closes the FileChannel and RandomAccessFile
            %   - Removes the .lock file
            %   - Updates the internal locked state
            %   - Safe to call multiple times (issues warning if not locked)
            %
            % Exceptions:
            %   SimpleFileMutex:NotLocked - Warning if mutex is not currently locked
            %   SimpleFileMutex:UnlockFailed - If lock release fails
            %
            % Examples:
            %   mutex = SimpleFileMutex('data.mat');
            %   mutex.lock();
            %   % ... perform file operations ...
            %   mutex.unlock();  % Release the lock
            %
            % Notes:
            %   - Always call unlock() after lock() to prevent deadlocks
            %   - The destructor will automatically call unlock() if needed
            %   - Consider using try-catch blocks to ensure unlock() is called
            
            if ~obj.isLocked
                warning('SimpleFileMutex:NotLocked', 'Mutex is not currently locked by this instance');
                return;
            end
            
            try
                % Release Java FileLock and close file handles
                if ~isempty(obj.fileLock)
                    obj.fileLock.release();
                    obj.fileLock = [];
                end
                
                if ~isempty(obj.lockChannel)
                    obj.lockChannel.close();
                    obj.lockChannel = [];
                end
                
                if ~isempty(obj.lockFile)
                    obj.lockFile.close();
                    obj.lockFile = [];
                end
                
                % Remove the lock file
                if isfile(obj.lockFilePath)
                    delete(obj.lockFilePath);
                end
                
                obj.isLocked = false;
                
            catch ME
                % Ensure cleanup even on error
                obj.cleanupJavaObjects();
                obj.isLocked = false;
                
                warning('SimpleFileMutex:UnlockFailed', 'Failed to release lock: %s', ME.message);
                rethrow(ME);
            end
        end
    end
    
    methods (Access = private)
        function cleanupJavaObjects(obj)
            % cleanupJavaObjects - Internal method to clean up Java objects
            %
            % This method safely closes and clears all Java objects used for 
            % file locking. It's called during error recovery and cleanup.
            
            try
                if ~isempty(obj.fileLock)
                    obj.fileLock.release();
                end
            catch
                % Ignore errors during cleanup
            end
            
            try
                if ~isempty(obj.lockChannel)
                    obj.lockChannel.close();
                end
            catch
                % Ignore errors during cleanup
            end
            
            try
                if ~isempty(obj.lockFile)
                    obj.lockFile.close();
                end
            catch
                % Ignore errors during cleanup
            end
            
            obj.fileLock = [];
            obj.lockChannel = [];
            obj.lockFile = [];
        end
    end
end