function results = parallelComputation(handles)
%PARALLELCOMPUTATION Tracks path of cropped image.
%   handles = PARALLELCOMPUTATION(handles) returns 
%
%   See also: CONVENTIONALCOMPUTATION, COMPUTE2DNERVEKINEMATICS.
%==========================================================================

%%% Try to restrict the correlation matching to a region immediately
%%% around the bone crop frame-by-frame


% Assign variables from saved data for readability.
Ia  = handles.figure1.UserData.AdjustedImage;       % Image following button #2.
nerveCrop	= handles.figure1.UserData.NerveCrop; 	% Original pos of box in nerve.
nerveMask	= handles.figure1.UserData.NerveMask;  	% Image data of ^.
boneCrop	= handles.figure1.UserData.BoneCrop;
boneMask	= handles.figure1.UserData.BoneMask;
correlationThreshold	= handles.edit_CorrelationThreshold.Value;

% Compute initial correlation matching between original and rounded crop.
corrScoreMN	= corrMatching(Ia,nerveMask,correlationThreshold);
corrScoreB	= corrMatching(Ia,boneMask,correlationThreshold);

% Find, plot the 1st location of centroid;
[nerveY,nerveX]	= find(corrScoreMN == max(corrScoreMN(:)));
[datumY,datumX]	= find(corrScoreB == max(corrScoreB(:)));

% Ensure all frames of the ultrasound are in the same folder.
cd(handles.figure1.UserData.PathName);              % Original file location.
files	= dir('*.tif');                         	% All ultrasound frames.
numFiles= size(files,1);

% Compute new location and velocity between correlated position across frames.
nerveXYshift= [nerveX - nerveCrop(1), nerveY - nerveCrop(2)];
boneXYshift	= [datumX - boneCrop(1), datumY - boneCrop(2)];

%% For nested within parfor.
% Create necessary broadcast variables for parallel computation.
I   = cell(numFiles,2);                             % All image file data.
wb  = waitbar(0,'Reading Image Files (0.00%)...');
for idx = 1:numFiles
    I{idx,1}	= files(idx).name;                  % Retrieve next frame.
    if strfind(I{idx,1},'.tif') > 0                 % All but original frame.
        I{idx,2}	= imread([handles.figure1.UserData.PathName,I{idx,1}]);
    else
        I{idx,2}	= [];
    end
    waitbar(idx/numFiles,wb,['Reading Image Files (',...
        num2str(round((idx/numFiles)*100)),'%)...']);
end

% Create splicing variables for parallel computation.
results	= cell(2,1);

% Perform parallel computation of crops' tracking throughout image.
waitbar(0,wb,'Starting parallel computations (0.00%)...');
parfor idx = 1:2                                    % Nerve -> 1, bone -> 2
    % Create temporary variables.
    tic
    Image   = I;
    XY      = cell(numFiles,2)
    masks   = cell(numFiles,1);
    crops   = masks;
    if idx == 1
        XYshift = nerveXYshift;
        masks{1}= nerveMask;
        crops{1}= nerveCrop;
    else
        XYshift	= boneXYshift;
        masks{1}= boneMask;
        crops{1}= boneCrop;
    end
    kdx = 1;                                        % Index to images.
    for jdx = 1:numFiles
%         waitbar(idx/numFiles,wb),['Tracking locations of items (',...
%             num2str(round((idx/numFiles)*100)),'%)...']);
        if strfind(Image{idx,1},'.tif') == 0       	% Skip unread images.
            continue
        end
        
        % Compute correlation score for the median nerve new location.
        corrScore	= corrMatching(Image{kdx,2},masks{jdx},correlationThreshold);
        
        % Compute new location for mask of nerve.
        [~,foundMax]= max(corrScore(:));           % Row, col indices of max.
        [XY{jdx,1},XY{jdx,2}]	= ind2sub(size(corrScore),foundMax);
        
        % Calculate x-y coordinate shift from previous bounding box of mask.
        crops{jdx+1}= [XY{jdx,1}-XYshift(1), XY{jdx,2}-XYshift(2), crops{jdx}(3:4)];
        
        % Update cropped image and waitbar.
        masks{jdx+1}= imcrop(I{kdx,2},crops{jdx+1});
        kdx = kdx + 1;
    end
    results{idx} = {XY,masks,crops};toc
end
delete(gcp('nocreate'));

%% Compute 2D Kinematics.
nerveX  = cell2mat(results{1}{1}(:,1));         	% Unpack variables.
nerveY  = cell2mat(results{1}{1}(:,2));
nerveMask	= results{1}{2}(:,1);
nerveCrop   = cell2mat(results{1}{3}(:,1));
boneX	= cell2mat(results{2}{1}(:,1));
boneY	= cell2mat(results{2}{1}(:,1));
boneMask	= results{2}{2}(:,1);
boneCrop	= cell2mat(results{2}{3}(:,1));
initData= zeros(numFiles,2);
data    = struct('NerveXY',[nerveX nerveY],'BoneXY',[boneX boneY],...
    'RelativeXY',[nerveX nerveY]-repmat([boneX(1) boneY(1)],numFiles,1),...
    'MotionPath',initData,...                       % ^ in X-Y coordinates.
    'AxialDisplacement',initData(1:end-1,:),...     % X,Y distances between centers.
    'LinearDistance',initData(1:end-1,1),...        % Pythagorean theorem of ^.
    'Velocity',[0; initData(1:end-1,1)],...         % Begin with zero velocity.
    'Acceleration',[0; initData(1:end-1,1)],...   	% Begin with zero accel.
    'XValues',(0:1:size(files,1)).*...              % Graph x-values; [s/frame]*[frames] = [s]
    handles.figure1.UserData.FrameScaling);
data.MotionPath	= data.RelativeXY.*handles.figure1.UserData.MillimetersPerPixel;
data.AxialDisplacement	= diff(data.MotionPath);
data.LinearDistance	= hypot(data.AxialDisplacement(:,1),...
    data.AxialDisplacement(:,2));
data.Velocity	= data.LinearDistance.*handles.figure1.UserData.FrameScaling;
data.Acceleration	= diff(data.Velocity);

%% Plot results.
for ldx = 1:numFiles
    pause(.25);
    if strfind(I{ldx,1},'.tif') == 0                % Skip unread images.
        continue
    end
    % Plot next ultrasound frame on main axis.
    delete(findobj(handles.axis_PlotUltrasoundImage.Children,'type','image'));
    imshow(I{ldx,2},'Parent',handles.axis_PlotUltrasoundImage);
    set(handles.axis_PlotUltrasoundImage.Title,...
        'Interpreter','None','string',['Carpal Tunnel Ultrasound: ',...
        handles.figure1.UserData.FileName(1:end-4),' Frame #',num2str(ldx)],...
        'FontWeight','bold','FontName','Open Sans','FontSize',12);
    
    % Bring text labels to front of axis children.
    % uistack(findobj(handles.axis_PlotUltrasoundImage,'type','text'),'bottom');
    handles	= showCropLabels(handles);
    
    % Plot new location of nerve and bone crops.
    iterStr = num2str(ldx);
    rectangle('Parent',handles.axis_PlotUltrasoundImage,...
        'Position',nerveCrop(ldx,:),'EdgeColor','r',...
        'LineStyle',':','tag',['Nerve Box, iter: ',iterStr],...
        'visible',handles.button_BoundingBoxDisplay.UserData);
    rectangle('Parent',handles.axis_PlotUltrasoundImage,...
        'Position',boneCrop(ldx,:),'EdgeColor','g',...
        'LineStyle',':','tag',['Bone Box, iter: ',iterStr],...
        'visible',handles.button_BoundingBoxDisplay.UserData);
    plot(nerveX(ldx),nerveY(ldx),'r*',...
        'visible',handles.button_CurrentLocationDisplay.UserData);
    plot(boneX(ldx),boneX(ldx),'g*',...
        'visible',handles.button_CurrentLocationDisplay.UserData);
    if strcmpi(handles.button_PreviousLocationsDisplay.UserData,'off')
        lineInPlot  = findobj(handles.axis_PlotUltrasoundImage,'type','line');
        recInPlot	= findobj(handles.axis_PlotUltrasoundImage,'type','rectangle');
        set([lineInPlot(1:end-2); recInPlot(1:end-2)],'visible','off');
    end
    if handles.figure1.UserData.DrawDecision == 1
        drawnow;
    end
    
    % Update plot values second (bottom) axis.
    if ldx == 1                                 	% Position X,Y data.
        handles.axis_PlotTrackingData.Children(1).XData	= data.MotionPath(ldx,1);
        handles.axis_PlotTrackingData.Children(1).YData = data.MotionPath(ldx,2);
    else
        handles.axis_PlotTrackingData.Children(1).XData =...
            [handles.axis_PlotTrackingData.Children(1).XData, data.MotionPath(ldx,1)];
        handles.axis_PlotTrackingData.Children(1).YData =...
            [handles.axis_PlotTrackingData.Children(1).YData, data.MotionPath(ldx,2)];
    end
    handles.axis_PlotTrackingData.Children(2).XData	=...% Velocity X data.
        [handles.axis_PlotTrackingData.Children(2).XData, data.XValues(ldx)];
    handles.axis_PlotTrackingData.Children(2).YData =...% Velocity Y data.
        [handles.axis_PlotTrackingData.Children(2).YData, data.Velocity(ldx)];
    handles.axis_PlotTrackingData.Children(3).XData =...% Accel. X data.
        [handles.axis_PlotTrackingData.Children(3).XData, data.XValues(ldx)];
    handles.axis_PlotTrackingData.Children(3).YData =...% Accel. Y data.
        [handles.axis_PlotTrackingData.Children(3).YData, data.Acceleration(ldx)];
    if handles.figure1.UserData.DrawDecision == 1
        drawnow;
    end
    
    % Update cropped image.
    imshow(nerveMask{ldx},'Parent',handles.axis_PlotCroppedImage);
    set(handles.axis_PlotCroppedImage.Title,'Interpreter','None','string',...
        'Mask of Median Nerve','FontWeight','bold','FontName','Open Sans','FontSize',12);
end

