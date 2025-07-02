function direct_writer(filename, threadId, writesPerThread)
    % DIRECT_WRITER - Write thread ID to file multiple times without mutex protection
    % This function demonstrates direct file access that can lead to race conditions
    % when multiple threads access the same file concurrently.
    %
    % Inputs:
    %   filename - Path to the file to write to
    %   threadId - Unique identifier for this thread
    %   writesPerThread - Number of times to write the thread ID
    
    try
        % Open file in append mode (creates file if it doesn't exist)
        fid = fopen(filename, 'a+');
        
        if fid == -1
            error('Failed to open file: %s', filename);
        end
        
        % Write thread ID the specified number of times
        for i = 1:writesPerThread
            fprintf(fid, '%d ', threadId);

            % Add small random delay to increase chance of race conditions
            pause(rand() * 0.01); % 0-10ms random delay
        end
        fprintf(fid, '\n'); 
        
        % Close the file
        fclose(fid);
        
    catch ME
        % Ensure file is closed even if error occurs
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
        
        % Re-throw the error
        rethrow(ME);
    end
end

