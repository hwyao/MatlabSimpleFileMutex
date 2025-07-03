% Simple example demonstrating concurrent file access with SimpleFileMutex
% This example uses .NET Process to create true multithreading

% Suppress warnings about unreached code
%#ok<*UNRCH>

clc; clear;

% Setup test parameters
testFile = fullfile(pwd, 'example', 'mutex_demo.txt');
numberOfThreads = 5;
writesPerThread = 100;

% Configure the example
enable_mutex = true; % Set to false to test without mutex, true to use mutex

% Clean up any existing files
if isfile(testFile)
    delete(testFile);
end
lockFile = [testFile '.lock'];
if isfile(lockFile)
    delete(lockFile);
end

% Initialize empty file
fid = fopen(testFile, 'w');
fclose(fid);

fprintf('Starting %d threads, each writing %d numbers...\n', numberOfThreads, writesPerThread);
if enable_mutex
    fprintf('This demo uses MUTEX PROTECTION to prevent race conditions\n\n');
else
    fprintf('This demo uses DIRECT file access (no mutex) to show race conditions\n\n'); 
end

% Add .NET assembly
NET.addAssembly('System');

% Choose writer script based on mutex setting
if enable_mutex
    writerScript = 'writer_with_mutex';
else
    writerScript = 'writer_without_mutex';
end

% Create and start MATLAB processes for concurrent writing
processes = cell(numberOfThreads, 1);
for threadId = 1:numberOfThreads
    process = System.Diagnostics.Process();
    process.StartInfo.FileName = 'matlab';
    
    % Command to run the writer script with parameters
    command = sprintf('openProject(''MatlabSimpleFileMutex.prj'');filename=''%s''; threadId=%d; writesPerThread=%d; %s; exit;', ...
        testFile, threadId, writesPerThread, writerScript);
    
    process.StartInfo.Arguments = sprintf('-nosplash -batch "%s"', command);
    process.StartInfo.UseShellExecute = true;
    process.StartInfo.CreateNoWindow = false;
    
    processes{threadId} = process;
end

for threadId = 1:numberOfThreads
    processes{threadId}.Start();
    fprintf('Started thread %d (PID: %d)\n', threadId, processes{threadId}.Id);
end

% Wait for all processes to complete
fprintf('Waiting for threads to complete...\n');
maxWaitTime = 90; % seconds
startTime = tic;

while toc(startTime) < maxWaitTime
    allCompleted = true;
    for i = 1:numberOfThreads
        if ~processes{i}.HasExited
            allCompleted = false;
            break;
        end
    end
    
    if allCompleted
        break;
    end
    
    pause(1);
end

% Check results
completedCount = 0;
for i = 1:numberOfThreads
    if processes{i}.HasExited
        completedCount = completedCount + 1;
        fprintf('Thread %d completed with exit code: %d\n', i, processes{i}.ExitCode);
    else
        fprintf('Thread %d still running, terminating...\n', i);
        processes{i}.Kill();
    end
end

fprintf('\n%d/%d threads completed successfully\n', completedCount, numberOfThreads);

% Output the contents of the test file
pause(5);
text = fileread(testFile);
fprintf('\nContents of %s:\n', testFile);
disp(text);
fprintf('\nExample completed!\n');

