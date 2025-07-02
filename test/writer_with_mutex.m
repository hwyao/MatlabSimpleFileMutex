mutex = SimpleFileMutex(filename);
mutex.lock();
direct_writer(filename, threadId, writesPerThread)
mutex.unlock();
