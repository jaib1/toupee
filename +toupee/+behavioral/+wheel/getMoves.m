function ...
    [moveOn, moveOff, moveDisplacement, moveDirection, moveClass, ...
     movePeakVelocity, movePeakAcceleration] =  getMoves(x, t, varargin)
% Gets and classifies wheel moves
%
% A wheel move can only be in one direction.
% Algorithm (pseudocode):
% >> for each sample
%     >> if displacement b/w (sample) : (`tThresh` samples) > `xThresh`
%           >> (sample) : (sample of max displacement) belong to a movement
% >> find all movement starts
% >> for all movements
%     >> merge consecutive, same-direction movements that are separated by 
%     less than `tMinGap` seconds
%     >> find more exact movement start by looking in future (from
%     predefined movement start) for first sample with diff greater than
%     `xOnThresh`
%     >> find more exact end of movement by looking in future (from
%     predefined movement end) for first sample with diff less than 
%     `xOffThresh` 
% >> get duration of each movement and discard movements with duration less
% than `minDur`
% >> get total displacement of each movement
% >> get direction of each movement
% >> classify each movement ("flinch" if movement duration < `tThresh`)
% >> get velocity and acceleration of each movement
%
% 
% Inputs:
% -------
% x : double array
%   Contains the wheel position (in m) at each sample.
% 
% t : double array
%   Contains the timestamp (in s) of each sample.
% 
% 'fs' : int scalar (optional name-value pair)
%   The sampling frequency (in hz) of the wheel. (Default: 1000 hz)
%
% 'xThresh' : double scalar (optional name-value pair)
%   The minimum change in position (in m) of the wheel (within `tThresh`) 
%   for it to be classified as a movement. (Default: 0.0015 m)
%
% 'tThresh' : double scalar (optional name-value pair)
%   The maximum duration (in s) in which the wheel position must change by
%   at least `xThresh` for it to be classified as a movement. 
%   (Default: 0.150 s)
%
% 'tMinGap' : double scalar (optional name-value pair)
%   The minimum duration (in s) between consecutive wheel movements for the
%   movements to be considered separate. (Default: 0.1 s)
% 
% 'xOnThresh' : double scalar (optional name-value pair)
%   The minimum change in position (in m) of the wheel for a more exact
%   wheel movement start time to be defined from an initial wheel movement
%   start time. (Default: 0.0005 m)
%
% 'xOffThresh' : double scalar (optional name-value pair)
%   The maximum allowable change in position (in m) of the wheel for a more
%   exact wheel movement end time to be defined from an initial wheel
%   movement end time. (Default: 0.0005 m)
%
% 'minDur' : double scalar (optional name-value pair)
%   The minimum duration (in s) a wheel movement must take place over for
%   it not to be discarded. (Default: 0 s)
%
% 'getVelAcc' : logical (optional name-value pair)
%   A flag for computing the velocity and acceleration of each move.
%   (Default: true)
%
% 'gradFn' : function handle (optional name-value pair)
%   A function handle containing the function to use on the wheel position
%   data to compute the wheel velocity. (Default: The numerical gradient of
%   a single-pass, moving-average with a 10 ms window)
%   
% 'makePlots' : logical (optional name-value pair)
%   A flag for plotting the detected wheel moves. (Default: false)
%
%
% Outputs:
% --------
% moveOn : double array
%   The times (in s) each movement began.
%
% moveOff : double array
%   The times (in s) each movement ended.
%
% moveDisplacement : double array 
%   The change in position (in m) of each movement.
% 
% moveDirection : cell array
%   The direction ('left' or 'right') of each movement.
%
% moveClass : cell array
%   The class ('flinch' or 'smooth') of each movement.
%
% movePeakVelocity : double array
%   The peak velocity (in m/s) of each movement.
%
% movePeakAcceleration : double array
%   The peak acceleration (in m/s^2) of each movement.
%
%
% Examples:
% ---------
%

%% Prerun checks.
% Imports.
import toupee.misc.*
import toupee.behavioral.wheel.*
% Turn off warnings for assigning to a subset of rows of a table at a time.
warning('off', 'MATLAB:table:RowsAddedNewVars')
warning('off', 'MATLAB:table:RowsAddedExistingVars')
% Validate inputs.
p = inputParser;
isValidX = @(y) isnumeric(y) && isvector(y) && numel(y) == numel(t);
isValidT = @(y) isnumeric(y) && isvector(y) && numel(y) == numel(x);
isValidNum = @(y) isnumeric(y) && isscalar(y) && (y > 0);
isValidFlag = @(y) islogical(y) && isscalar(y);
isValidGradFn = @(y) isa(y, 'function_handle');

addRequired(p, 'x', isValidX);
addRequired(p, 't', isValidT);
addParameter(p, 'fs', 1000, isValidNum);
addParameter(p, 'xThresh', 0.0015, isValidNum);
addParameter(p, 'tThresh', 0.150, isValidNum);
addParameter(p, 'tMinGap', 0.1, isValidNum);
addParameter(p, 'xOnThresh', 0.0005, isValidNum);
addParameter(p, 'xOffThresh', 0.0005, isValidNum);
addParameter(p, 'minDur', 0, isValidNum);
addParameter(p, 'getVelAcc', true, isValidFlag);
addParameter(p, 'gradFn', @(y) gradient(movmean(y, 10)), isValidGradFn);
addParameter(p, 'makePlots', false, isValidFlag);

parse(p, x, t, varargin{:});
p = p.Results;  % final parameters

%% Compute approximate movement start and end times.
% Convert the time threshold for detecting movements into a number of 
% samples threshold (given the sampling frequency)
sThresh = round(p.tThresh * p.fs);
nS = numel(t);  % total number of samples
% For each sample, see if it belongs to a movement.
% Values of `1` in `moveMask` correspond to samples belonging to a 
% rightwards move, while values of `-1.1` correspond to samples belonging 
% to a leftwards move.
dirS = zeros(nS, 1);  % direction of movement of samples
for iS = 1:(nS - sThresh)
    % Find all current samples that pass thresh for movement. If none do,
    % continue with the next sample.
    % displacement for current samples: negative vals mean x is increasing,
    % so rightwards turn, and positive vals mean vice versa
    disCur = x(iS) - x((iS + 1):(iS + sThresh));
    moveMaskCur = abs(disCur) > p.xThresh;
    if ~any(moveMaskCur), continue, end
    % Find direction of first change in position.
    moveDirCur = sign(-disCur(find(disCur, 1, 'first')));
    % If the change in this direction *doesn't* break movement threshold,
    % continue to next sample.
    disDirCur = sign(diff([-disCur(1); -disCur(moveMaskCur)]));
    if ~(disDirCur(1) == moveDirCur)
        continue
    % Else, find the last continuous position change in this direction.
    else
        moveIdxsCur = find(moveMaskCur);
        iEndMove = find(sign(diff(-disCur(moveMaskCur))) ...
                        == -moveDirCur, 1, 'first');
        % If it's a continuous movement in one direction, mark the end of
        % the movement as the last sample of the current sample subset.
        if isempty(iEndMove), iEndMove = numel(moveIdxsCur); end
        iEndMove = moveIdxsCur(iEndMove);
        dirS(iS:(iS + iEndMove)) = moveDirCur;
    end
end
% Allow for differentiating movement types based on diffs. (If 0-to-left
% moves were kept as `-1`, then it wouldn't be possible to differentiate
% 0-to-left from right-to-0 moves).
dirS(dirS == -1) = -1.1;
% Make sure final sample allows for a movement end.
dirS((end - 1) : end) = false;

%% Check whether to merge some movements.
% Find all movement starts.
z2r = find(diff(dirS) == 1);     % 0-to-right moves
l2r = find(diff(dirS) == 2.1);   % left-to-right moves
z2l = find(diff(dirS) == -1.1);  % 0-to-left moves
r2l = find(diff(dirS) == -2.1);  % right-to-left moves
% specific move type for each move
moveTypes = [(zeros(numel(z2r), 1) + 1); ...  
             (zeros(numel(l2r), 1) + 2.1); ... 
             (zeros(numel(z2l), 1) - 1.1); ...  
             (zeros(numel(r2l), 1) - 2.1)];
% Sort movement starts in time.
[startS, sIdxs] = sort([z2r; l2r; z2l; r2l]);
startS = startS + 1;
moveTypes = moveTypes(sIdxs);
% Merge consecutive, same-direction movements that are separated by less
% than `p.tMinGap`
inMinGapMoves = find(diff(startS) < (p.tMinGap * p.fs));
inSameDirMoves = find(diff(sign(moveTypes)) == 0);
% Get moves that should be merged with subsequent moves.
mergeeMoves = intersect(inMinGapMoves, inSameDirMoves);
if ~isempty(mergeeMoves)
    % Get subsequent moves that should be merged with `mergeeMoves`.
    mergerMoves = mergeeMoves + 1;
    % Fill in the indices in `sDir` between the moves that should be merged
    % with info on the type of move.
    fillIdxs = arrayfun(@(z, z2) [z:1:z2]', startS(mergeeMoves), ... 
                        startS(mergerMoves), 'uni', 0);
    fillVals = cellfun(@(z, z2) zeros(numel(z), 1) + moveTypes(z2),...
                       fillIdxs, num2cell(mergeeMoves), 'uni', 0);
    for iM = 1:numel(mergeeMoves)
        dirS(fillIdxs{iM}) = fillVals{iM};
    end
    % After merging, find all movement starts again.
    z2r = find(diff(dirS) == 1);     % 0 to right
    l2r = find(diff(dirS) == 2.1);   % left to right
    z2l = find(diff(dirS) == -1.1);  % 0 to left
    r2l = find(diff(dirS) == -2.1);  % right to left
    % specific move type for each move
    moveTypes = [(zeros(numel(z2r), 1) + 1); ...
                 (zeros(numel(l2r), 1) + 2.1); ...
                 (zeros(numel(z2l), 1) - 1.1); ...
                 (zeros(numel(r2l), 1) - 2.1)];
    % Sort movement starts in time.
    [startS, sIdxs] = sort([z2r; l2r; z2l; r2l]);
    startS = startS + 1;
    moveTypes = moveTypes(sIdxs);
end

%% Compute more precise movement start and end times.
nMoves = numel(startS);
startS2 = startS;  % will hold more precise movement start samples
endS2 = zeros(nMoves, 1);  % will hold movement end samples
for iM = 1:nMoves
    % Get new estimate of movement start: for left (right) movements, find 
    % first sample after predefined movement start that decreases 
    % (increases) by at least `p.xOnThresh`.
    bookend = iif((startS(iM) + p.fs * 10) > nS, nS, ...
                  startS(iM) + p.fs * 10);
    iA = 1;  % index to add
    if moveTypes(iM) == -1.1  % left
        iA = find(x(startS(iM):bookend) < (x(startS(iM)) - p.xOnThresh),...
                  1, 'first');
    elseif moveTypes(iM) == 1  % right
        iA = find(x(startS(iM):bookend) > (x(startS(iM)) + p.xOnThresh),...
                  1, 'first');
    end
    if isempty(iA), iA = 1; end
    startS2(iM) = startS(iM) + iA - 1;
    % Get new estimate of movement end: find the first sample after the
    % predefined movement end that has an abs diff of < `p.xOffThresh`
    bookend = iif((startS2(iM) + p.fs * 10) > nS, nS, ...
                  startS2(iM) + p.fs * 10);
    iA = find(dirS(startS2(iM):bookend) ~= dirS(startS2(iM)), 1, 'first');
    if isempty(iA), iA = 1; end
    endS = startS2(iM) + iA - 1;  % predefined movement end
    bookend = iif((endS + p.fs * 10) > nS, nS, endS + p.fs * 10);
    iA = find(abs(diff(x(endS:bookend))) < p.xOffThresh, 1, 'first'); 
    if isempty(iA), iA = 1; end
    endS2(iM) = endS + iA;
end

%% Return Outputs.
moveOn = startS2 / p.fs;
moveOff = endS2 / p.fs;
moveDur = moveOff - moveOn;
% Remove movements below the minimum duration thresh.
moveDurMask = moveDur > p.minDur;
startS2 = startS2(moveDurMask);
endS2 = endS2(moveDurMask);
nMoves = numel(startS2);
moveOn = startS2 / p.fs;
moveOff = endS2 / p.fs;
moveTypes = moveTypes(moveDurMask);
moveDirection = cell(nMoves, 1);
moveDirection(moveTypes == -2.1) = {'right-to-left'};
moveDirection(moveTypes == -1.1) = {'zero-to-left'};
moveDirection(moveTypes == 1) = {'zero-to-right'};
moveDirection(moveTypes == 2.1) = {'left-to-right'};
moveDur = moveOff - moveOn;
moveDisplacement = x(endS2) - x(startS2);
moveClass = repmat({'smooth'}, [nMoves, 1]);
moveClass(moveDur < 0.1) = {'flinch'};

if p.getVelAcc
    % Get continuous velocity and acceleration for each move.
    [moveV, moveA] = ...
        arrayfun(@(z, z2) computeVelAcc(x(z:z2), t(z:z2), 'fs', p.fs, ...
                                        'gradFn', p.gradFn), ...
                                        startS2, endS2, 'uni', 0);
    % Get peak velocity and acceleration from continuous values.
    movePeakVelocity = zeros(nMoves, 1);
    movePeakAcceleration = zeros(nMoves, 1);
    for iM = 1:nMoves
        vCur = moveV{iM};
        [~, iMaxV] = max(abs(vCur));
        movePeakVelocity(iM) = vCur(iMaxV);
        aCur = moveA{iM};
        [~, iMaxA] = max(abs(aCur));
        movePeakAcceleration(iM) = vCur(iMaxA);
    end
end

%% Plot position trace and velocity trace with overlaid moves.
if p.makePlots
    figure('Name', 'Wheel movements'); 
    % Plot the wheel position
    ax1 = subplot(2,1,1);
    hold on; 
    on = plot(moveOn, x(startS2), 'go', 'DisplayName', 'moveOn');
    off = plot(moveOff, x(endS2), 'bo', 'DisplayName', 'moveOff');
    hold on; 
    inMove = logical(withinRanges(t, [moveOn moveOff]));
    in = plot(t(inMove), x(inMove), 'r.', 'DisplayName', 'inMove');
    %plot(t(~inMove), x(~inMove), 'k.');
    ylabel('position');
    legend([on off in], 'Location', 'SouthEast')
    
    % Plot the velocity trace
    ax2 = subplot(2,1,2);
    vel = computeVelAcc(x, t);
    hold on; 
    plot(moveOn, vel(startS2), 'go');
    plot(moveOff, vel(endS2), 'bo');
    plot(t(inMove), vel(inMove), 'r.');
    %plot(t(~inMove), vel(~inMove), 'k.');
    ylabel('velocity');
    xlabel('time (sec)');
    
    linkaxes([ax1 ax2], 'x');
end

end