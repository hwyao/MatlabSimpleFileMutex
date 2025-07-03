% Hint: this is not a independend script. It is used by injection for .NET
% Program to start MATLAB again with scripts.
% filename, threadId, writesPerThread should be set in advance.
mutex = SimpleFileMutex(filename);
mutex.lock();
direct_writer(filename, threadId, writesPerThread)
mutex.unlock();
