function [expInfo, neuralData, behavioralData] = processExperiment(varargin)


%% load cell data
% regular, solo, or unmatched sessions
if nargin == 1 || strcmp(varargin{2},'unmatched')
    expInfo = varargin{1};
    expInfo = data.loadExpData(expInfo);
    [allFcell, expInfo] = loadCellData(expInfo);
    
% matched sessions
elseif nargin == 2 && strcmp(varargin{2},'matched')
    expInfo = varargin{1};
    expInfo = data.loadExpData(expInfo);
    [allFcell, expInfo] = loadMatchedCellData(expInfo);
   
% any other arguments will throw an error    
else
    error('Input an expInfo and "matched"/"unmatched" tag')
end
 
%% get event times

allEventTimes = getEventTimes(expInfo, {'stimulusOnTimes' 'interactiveOnTimes' 'stimulusOffTimes'});
allWheelMoves = getWheelMoves(expInfo, allEventTimes);

if length(allEventTimes) == length(allWheelMoves)
    behavioralData = struct('eventTimes',allEventTimes,'wheelMoves', allWheelMoves);
else
    error('Event/wheel experiment lengths do not match')
end

%% collate cell responses across planes

[cellResps, respTimes] = getCellResps(expInfo, allFcell);

%% assemble into relevant structs, for tidiness

neuralData = struct('allFcell',allFcell,'cellResps',cellResps,'respTimes',respTimes);

