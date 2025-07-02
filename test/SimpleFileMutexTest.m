classdef SimpleFileMutexTest < matlab.unittest.TestCase
    % SimpleFileMutexTest - Unit tests for SimpleFileMutex class
    % This test class verifies the functionality of the SimpleFileMutex
    % including concurrent access protection
    
    properties (TestParameter)
        numberOfThreads = {2, 5, 10}
        writesPerThread = {10, 20, 50}
    end
    
    properties
        testFile
        testDir
        mutex
        lockFile
    end

    methods (TestMethodSetup)
        function setupTest(testCase)
            % Setup for each test method
            testCase.testDir = tempdir;
            testCase.testFile = fullfile(testCase.testDir, 'test_concurrent_file.txt');
            testCase.lockFile = [testCase.testFile '.lock'];
            
            % Clean up any existing test files
            try
                if isfile(testCase.testFile)
                    delete(testCase.testFile);
                end
                if isfile(testCase.lockFile)
                    delete(testCase.lockFile);
                end
            catch ME
                testCase.fatalAssertError(ME, ...
                    'Failed to clean up test files by setup: %s', ME.message);
            end

            % Create the txt and the mutex instance
            fid = fopen(testCase.testFile, 'w');
            fclose(fid);
            testCase.mutex = SimpleFileMutex(testCase.testFile);
        end
    end
    
    methods (TestMethodTeardown)
        function teardownTest(testCase)
            % Cleanup after each test method
            
            % Ensure mutex is unlocked
            if ~isempty(testCase.mutex) && isvalid(testCase.mutex) && testCase.mutex.isLocked
                try
                    testCase.mutex.unlock();
                catch
                    % Ignore errors during cleanup
                end
            end
            clear testCase.mutex;
            
            % Clean up test files
            try
                if isfile(testCase.testFile)
                    delete(testCase.testFile);
                end
                if isfile(testCase.lockFile)
                    delete(testCase.lockFile);
                end
            catch ME
                testCase.fatalAssertError(ME, ...
                    'Failed to clean up test files by teardown: %s', ME.message);
            end
        end
    end
    
    methods (Test)
        function testBasicLockUnlock(testCase)
            % Test basic lock and unlock functionality
            
            % Initially no lock file should exist
            testCase.verifyFalse(isfile(testCase.lockFile), ...
                'Lock file should not exist initially');
            
            % Acquire lock
            testCase.mutex.lock();
            testCase.verifyTrue(isfile(testCase.lockFile), ...
                'Lock file should exist after lock()');
            
            % Release lock
            testCase.mutex.unlock();
            testCase.verifyFalse(isfile(testCase.lockFile), ...
                'Lock file should not exist after unlock()');
        end
        
        % function testConcurrentFileWrites(testCase, numberOfThreads, writesPerThread)
            
        % end
        
        function testConstructorInvalidInputs(testCase)
            % Test constructor with invalid input arguments
            
            % Test 1: Constructor with no arguments
            testCase.verifyError(@() SimpleFileMutex(), ...
                'SimpleFileMutex:InvalidInput', ...
                'Should throw error when no file path is provided');
            
            % Test 2: Constructor with empty file path
            testCase.verifyError(@() SimpleFileMutex(''), ...
                'SimpleFileMutex:InvalidInput', ...
                'Should throw error when empty file path is provided');
            
            % Test 3: Constructor with invalid file path type
            testCase.verifyError(@() SimpleFileMutex(123), ...
                'SimpleFileMutex:InvalidInput', ...
                'Should throw error when file path is not string or char');
        end
        
        function testConstructorFileNotFound(testCase)
            % Test constructor with non-existent file
    
            nonExistentFile = fullfile(testCase.testDir, 'nonexistent.txt');
            testCase.verifyError(@() SimpleFileMutex(nonExistentFile), ...
                'SimpleFileMutex:FileNotFound', ...
                'Should throw error when file does not exist');
        end
        
        function testConstructorInvalidParameters(testCase)
            % Test constructor with invalid parameter values
            
            % Test invalid UnexpectedRetryMax parameters
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'UnexpectedRetryMax', -1), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for negative UnexpectedRetryMax');
            
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'UnexpectedRetryMax', 1.5), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for non-integer UnexpectedRetryMax');
            
            % Test invalid PauseTimeByLocking parameters
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'PauseTimeByLocking', 0), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for zero PauseTimeByLocking');
            
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'PauseTimeByLocking', -0.1), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for negative PauseTimeByLocking');
        end
        
        function testUnlockNotLocked(testCase)
            % Test unlocking when not locked should issue warning
            
            testCase.verifyWarning(@() testCase.mutex.unlock(), ...
                'SimpleFileMutex:NotLocked', ...
                'Should warn when unlocking a non-locked mutex');
        end
        
        function testDoubleLocking(testCase)
            % Test double locking should issue warning
            
            testCase.mutex.lock();
            
            testCase.verifyWarning(@() testCase.mutex.lock(), ...
                'SimpleFileMutex:AlreadyLocked', ...
                'Second lock() call should issue warning');
            
            testCase.mutex.unlock();
        end

        function testNormalOperation(testCase)
            % Test normal operation of lock/unlock
            
            % Lock the mutex
            testCase.mutex.lock();
            testCase.verifyTrue(isfile(testCase.lockFile), ...
                'Lock file should exist after lock()');
            testCase.verifyTrue(testCase.mutex.isLocked, ...
                'Mutex should be locked after lock()');
            
            % Unlock the mutex
            testCase.mutex.unlock();
            testCase.verifyFalse(isfile(testCase.lockFile), ...
                'Lock file should not exist after unlock()');
            testCase.verifyFalse(testCase.mutex.isLocked, ...
                'Mutex should not be locked after unlock()');
        end

        function testDoubleMutex(testCase)
            % Test two mutexes competing for the same file lock
            % First mutex locks with timer-delayed unlock, second mutex waits
            
            % Create second mutex for the same file
            mutex2 = SimpleFileMutex(testCase.testFile);
            
            % First mutex (testCase.mutex) locks the file
            testCase.mutex.lock();
            testCase.verifyTrue(isfile(testCase.lockFile), ...
                'Lock file should exist after first mutex lock()');
            testCase.verifyTrue(testCase.mutex.isLocked, ...
                'First mutex should be locked');
            
            % Create timer to unlock first mutex after 5 seconds
            unlockTimer = timer('ExecutionMode', 'singleShot', ...
                               'StartDelay', 5, ...
                               'TimerFcn', @(~,~) testCase.mutex.unlock());
            start(unlockTimer);
            
            % Record start time for second mutex lock attempt
            startTime = tic;
            mutex2.lock();
            elapsedTime = toc(startTime);
            
            % Stop and clean up timer
            testCase.verifyTrue(strcmp(unlockTimer.Running, 'off'), ...
                'Unlock timer should have stopped');
            delete(unlockTimer);
            
            % Verify timing - should be at least 4 seconds
            testCase.verifyGreaterThan(elapsedTime, 4.9, ...
                'Second mutex should wait at least 4.9 seconds');
            
            % Verify second mutex now has the lock
            testCase.verifyTrue(isfile(testCase.lockFile), ...
                'Lock file should exist after second mutex lock()');
            testCase.verifyTrue(mutex2.isLocked, ...
                'Second mutex should be locked');
            testCase.verifyFalse(testCase.mutex.isLocked, ...
                'First mutex should be unlocked');
            
            % Test normal lock/unlock with second mutex
            mutex2.unlock();
            testCase.verifyFalse(isfile(testCase.lockFile), ...
                'Lock file should not exist after second mutex unlock()');
            testCase.verifyFalse(mutex2.isLocked, ...
                'Second mutex should be unlocked');
            
            % Test that first mutex can lock again
            testCase.mutex.lock();
            testCase.verifyTrue(isfile(testCase.lockFile), ...
                'Lock file should exist after first mutex re-lock()');
            testCase.verifyTrue(testCase.mutex.isLocked, ...
                'First mutex should be locked again');
            
            testCase.mutex.unlock();
            testCase.verifyFalse(isfile(testCase.lockFile), ...
                'Lock file should not exist after final unlock()');
        end

        function testMultipleLockUnlockCycles(testCase)
            % Test multiple lock/unlock cycles with the same mutex
            % Use the pre-built testCase.mutex
            
            for i = 1:5
                % Lock
                testCase.mutex.lock();
                testCase.verifyTrue(isfile(testCase.lockFile), ...
                    sprintf('Lock file should exist after lock() cycle %d', i));
                testCase.verifyTrue(testCase.mutex.isLocked, ...
                    sprintf('Mutex should be locked after lock() cycle %d', i));
                
                % Unlock
                testCase.mutex.unlock();
                testCase.verifyFalse(isfile(testCase.lockFile), ...
                    sprintf('Lock file should not exist after unlock() cycle %d', i));
                testCase.verifyFalse(testCase.mutex.isLocked, ...
                    sprintf('Mutex should not be locked after unlock() cycle %d', i));
            end
        end
        
        function testDestructorCleanup(testCase)
            % Test that destructor properly cleans up locked mutex
            % Note: This test needs to create and destroy a mutex object,
            % so we cannot use the pre-built testCase.mutex (it needs to persist)
            
            verifyDestructorFile = fullfile(testCase.testDir, 'valid_test.txt');
            verifyDestructorLockFile = [verifyDestructorFile '.lock'];
            
            % Create new mutex and lock it
            fid = fopen(verifyDestructorFile, 'w');
            fclose(fid);
            new_mutex = SimpleFileMutex(verifyDestructorFile);
            new_mutex.lock();
            testCase.verifyTrue(isfile(verifyDestructorLockFile), ...
                'Lock file should exist after lock()');
            
            % Clear the mutex object (triggers destructor)
            clear new_mutex;
            
            % Verify lock file is cleaned up
            testCase.verifyFalse(isfile(verifyDestructorLockFile), ...
                'Lock file should be cleaned up by destructor');

            % remove the file created for destructor test
            if isfile(verifyDestructorFile)
                delete(verifyDestructorFile);
            end
        end
    end
end