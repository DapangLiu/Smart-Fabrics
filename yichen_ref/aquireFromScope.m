function waveform = aquireFromScope(scopeObj, channel, numberPoints)
%% Check which scope is connected
scopeModel = regexp(query(scopeObj,'*IDN?'),',','split');
scopeModel = scopeModel{2};
infiniiumScope = isequal(scopeModel,'DSO90804A');

%% Get data from Scope for CH1
% Specify data from Channel 1
fprintf(scopeObj,[':WAVEFORM:SOURCE CHAN' num2str(channel)]); 
% Set timebase to main
% Set up acquisition type and count. 
if ~infiniiumScope,
    fprintf(scopeObj,':TIMEBASE:MODE MAIN');
    fprintf(scopeObj,':ACQUIRE:TYPE NORMAL');
    fprintf(scopeObj,':ACQUIRE:COUNT 1');
    fprintf(scopeObj,':WAV:POINTS:MODE RAW');
    fprintf(scopeObj,[':WAV:POINTS ' num2str(numberPoints)]);
else
    fprintf(scopeObj,':TIMEBASE:VIEW MAIN');
    fprintf(scopeObj,':ACQUIRE:MODE RTIME');
    fprintf(scopeObj,[':ACQUIRE:POINTS ' num2str(numberPoints)]);
end
% Now tell the instrument to digitize channel1
fprintf(scopeObj,[':DIGITIZE CHAN' num2str(channel)]);
% Wait till complete
operationComplete = str2double(query(scopeObj,'*OPC?'));
while ~operationComplete
    operationComplete = str2double(query(scopeObj,'*OPC?'));
end
% Get the data back as a WORD (i.e., INT16), other options are ASCII and BYTE
fprintf(scopeObj,':WAVEFORM:FORMAT WORD');
% Set the byte order on the instrument as well
fprintf(scopeObj,':WAVEFORM:BYTEORDER LSBFirst');
% Get the preamble block
preambleBlock = query(scopeObj,':WAVEFORM:PREAMBLE?');
% The preamble block contains all of the current WAVEFORM settings.  
% It is returned in the form <preamble_block><NL> where <preamble_block> is:
%    FORMAT        : int16 - 0 = BYTE, 1 = WORD, 2 = ASCII.
%    TYPE          : int16 - 0 = NORMAL, 1 = PEAK DETECT, 2 = AVERAGE
%    POINTS        : int32 - number of data points transferred.
%    COUNT         : int32 - 1 and is always 1.
%    XINCREMENT    : float64 - time difference between data points.
%    XORIGIN       : float64 - always the first data point in memory.
%    XREFERENCE    : int32 - specifies the data point associated with
%                            x-origin.
%    YINCREMENT    : float32 - voltage diff between data points.
%    YORIGIN       : float32 - value is the voltage at center screen.
%    YREFERENCE    : int32 - specifies the data point where y-origin
%                            occurs.
% Now send commmand to read data
fprintf(scopeObj,':WAV:DATA?');
% read back the BINBLOCK with the data in specified format and store it in
% the waveform structure. FREAD removes the extra terminator in the buffer
waveform.RawData = binblockread(scopeObj,'uint16'); fread(scopeObj,1);
% Read back the error queue on the instrument
instrumentError = query(scopeObj,':SYSTEM:ERR?');
while ~(isequal(instrumentError,['+0,"No error"' char(10)]) || isequal(instrumentError,['0' char(10)])),
    disp(['Instrument Error: ' instrumentError]);
    instrumentError = query(scopeObj,':SYSTEM:ERR?');
end
%% Process
% Extract the X, Y data 

% Maximum value storable in a INT16
maxVal = 2^16; 

%  split the preambleBlock into individual pieces of info
preambleBlock = regexp(preambleBlock,',','split');

% store all this information into a waveform structure for later use
waveform.Format = str2double(preambleBlock{1});     % This should be 1, since we're specifying INT16 output
waveform.Type = str2double(preambleBlock{2});
waveform.Points = str2double(preambleBlock{3});
waveform.Count = str2double(preambleBlock{4});      % This is always 1
waveform.XIncrement = str2double(preambleBlock{5}); % in seconds
waveform.XOrigin = str2double(preambleBlock{6});    % in seconds
waveform.XReference = str2double(preambleBlock{7});
waveform.YIncrement = str2double(preambleBlock{8}); % V
waveform.YOrigin = str2double(preambleBlock{9});
waveform.YReference = str2double(preambleBlock{10});
waveform.VoltsPerDiv = (maxVal * waveform.YIncrement / 8);      % V
waveform.Offset = ((maxVal/2 - waveform.YReference) * waveform.YIncrement + waveform.YOrigin);         % V
waveform.SecPerDiv = waveform.Points * waveform.XIncrement/10 ; % seconds
waveform.Delay = ((waveform.Points/2 - waveform.XReference) * waveform.XIncrement + waveform.XOrigin); % seconds

% Generate X & Y Data
waveform.XData = (waveform.XIncrement.*(1:length(waveform.RawData))) - waveform.XIncrement;
waveform.YData = (waveform.YIncrement.*(waveform.RawData - waveform.YReference)) + waveform.YOrigin; 