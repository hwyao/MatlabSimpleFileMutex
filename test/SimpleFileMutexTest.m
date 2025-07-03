classdef SimpleFileMutexTest < matlab.unittest.TestCase
    % SimpleFileMutexTest - Unit tests for SimpleFileMutex class
    % This test class verifies the functionality of the SimpleFileMutex
    % including concurrent access protection
    
    properties
        testFile
        testDir
        mutex
        lockFile
        timingTolerance = 0.1  % Adjust this value if system performance is insufficient
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
            
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'UnexpectedRetryMax', 'invalid'), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for non-numeric UnexpectedRetryMax');
            
            % Test invalid PauseTimeByLocking parameters
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'PauseTimeByLocking', 0), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for zero PauseTimeByLocking');
            
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'PauseTimeByLocking', -0.1), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for negative PauseTimeByLocking');
            
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'PauseTimeByLocking', 'invalid'), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for non-numeric PauseTimeByLocking');
            
            % Test invalid MaxWaitTime parameters
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'MaxWaitTime', -1), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for negative MaxWaitTime');
            
            testCase.verifyError(@() SimpleFileMutex(testCase.testFile, 'MaxWaitTime', 'invalid'), ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'Should throw error for non-numeric MaxWaitTime');
        end

        function testDefaultParameters(testCase)
            % Test that constructor sets correct default parameter values
            
            % Use the default mutex created in setupTest
            % Verify default values match the documented defaults
            testCase.verifyEqual(testCase.mutex.unexpectedRetryMax, 20, ...
                'Default unexpectedRetryMax should be 20');
            testCase.verifyEqual(testCase.mutex.pauseTimeByLocking, 0.1, ...
                'Default pauseTimeByLocking should be 0.1');
            testCase.verifyEqual(testCase.mutex.maxWaitTime, 0, ...
                'Default maxWaitTime should be 0');
            
            % Verify other initialized properties
            testCase.verifyEqual(testCase.mutex.targetFilePath, testCase.testFile, ...
                'Target file path should match input');
            testCase.verifyFalse(testCase.mutex.isLocked, ...
                'Mutex should not be locked initially');
            testCase.verifyEqual(testCase.mutex.unexpectedRetryCount, 0, ...
                'Unexpected retry count should be 0 initially');
            
            % Verify processId format
            testCase.verifyMatches(testCase.mutex.processId, 'MATLAB_\d+', ...
                'Process ID should match MATLAB_<number> format');
            
            % Verify lock file path
            expectedLockPath = [testCase.testFile '.lock'];
            testCase.verifyEqual(testCase.mutex.lockFilePath, expectedLockPath, ...
                'Lock file path should be target file path with .lock extension');
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
            
            % Verify timing - should be approximately 5 seconds
            testCase.verifyEqual(elapsedTime, 5, 'AbsTol', testCase.timingTolerance, ...
                sprintf('Second mutex should wait approximately 5 seconds (±%.1fs). If this test fails frequently, consider increasing timingTolerance due to system performance limitations.', testCase.timingTolerance));
            
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

        function testMaxWaitTime(testCase)
            % Test that mutex respects the maximum wait time
            
            % Test 1: MaxWaitTime = 5s, unlock after 2s, should succeed
            mutex2 = SimpleFileMutex(testCase.testFile, 'MaxWaitTime', 5);
            
            % Lock first mutex
            testCase.mutex.lock();
            testCase.verifyTrue(testCase.mutex.isLocked, 'First mutex should be locked');
            
            % Create timer to unlock first mutex after 2 seconds
            unlockTimer1 = timer('ExecutionMode', 'singleShot', ...
                                'StartDelay', 2, ...
                                'TimerFcn', @(~,~) testCase.mutex.unlock());
            start(unlockTimer1);
            
            % Record start time and try to lock second mutex (should succeed)
            startTime1 = tic;
            mutex2.lock();  % Should succeed within 5s timeout
            elapsedTime1 = toc(startTime1);
            
            % Clean up timer
            delete(unlockTimer1);
            
            % Verify timing and lock acquisition
            testCase.verifyEqual(elapsedTime1, 2, 'AbsTol', testCase.timingTolerance, ...
                sprintf('Should wait approximately 2 seconds (±%.1fs). If this test fails frequently, consider increasing timingTolerance due to system performance limitations.', testCase.timingTolerance));
            testCase.verifyTrue(mutex2.isLocked, 'Second mutex should be locked');
            testCase.verifyFalse(testCase.mutex.isLocked, 'First mutex should be unlocked');
            
            % Unlock second mutex for next test
            mutex2.unlock();
            
            % Test 2: MaxWaitTime = 5s, unlock after 8s, should timeout
            % Lock first mutex again
            testCase.mutex.lock();
            testCase.verifyTrue(testCase.mutex.isLocked, 'First mutex should be locked for second test');
            
            % Create timer to unlock first mutex after 8 seconds
            unlockTimer2 = timer('ExecutionMode', 'singleShot', ...
                                'StartDelay', 8, ...
                                'TimerFcn', @(~,~) testCase.mutex.unlock());
            start(unlockTimer2);
            
            % Try to lock second mutex (should timeout after 5s)
            startTime2 = tic;
            testCase.verifyError(@() mutex2.lock(), ...
                'SimpleFileMutex:TimeoutExceeded', ...
                'Second mutex should timeout after 5 seconds');
            elapsedTime2 = toc(startTime2);
            
            % Clean up timer
            testCase.verifyTrue(strcmp(unlockTimer2.Running, 'on'), ...
                'Unlock timer should still be running');
            stop(unlockTimer2);
            delete(unlockTimer2);
            
            % Verify timeout behavior
            testCase.verifyEqual(elapsedTime2, 5, 'AbsTol', testCase.timingTolerance, ...
                sprintf('Should timeout after approximately 5 seconds (±%.1fs). If this test fails frequently, consider increasing timingTolerance due to system performance limitations.', testCase.timingTolerance));
            testCase.verifyFalse(mutex2.isLocked, 'Second mutex should not be locked after timeout');
            testCase.verifyTrue(testCase.mutex.isLocked, 'First mutex should still be locked');
            
            % Clean up - unlock first mutex
            testCase.mutex.unlock();
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