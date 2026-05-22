function setup = setup_detection_gui(video, defaultFrame)
%SETUP_DETECTION_GUI Collect direction, vertical width calibration, frame range.
%   video        : VideoReader object
%   defaultFrame : frame to show initially (default: middle frame)
%   setup        : struct, or [] if cancelled. Fields:
%     propagationDirection ('LtoR'|'RtoL'), scanDir (+1|-1),
%     calibFrame, yTop, yBottom, pixelHeight, yRows, chamberWidth_in,
%     mperpix, startFrame, endFrame
    setup = [];
    totalFrames = video.NumFrames;
    if nargin < 2 || isempty(defaultFrame)
        defaultFrame = round(totalFrames/2);
    end
    frameNumber = max(1, min(defaultFrame, totalFrames));

    % --- state shared with callbacks ---
    yTop = []; yBottom = []; calibFrame = [];
    startFrame = []; endFrame = []; chamberWidth_in = [];
    calibMode = false; calibClicks = [];
    doneFlag = false; cancelled = false;
    hCalibLines = gobjects(0);

    hFig = figure('Name','Detection Setup','NumberTitle','off', ...
        'WindowState','maximized','Color','w','CloseRequestFcn',@cbClose);
    hAx = axes('Parent',hFig,'Units','normalized','Position',[0.02 0.20 0.96 0.78]);
    axis(hAx,'off');
    hImg = imshow(read(video, frameNumber), 'Parent', hAx);
    hold(hAx,'on');

    % green full-screen crosshair cursor
    set(hFig,'Pointer','custom','PointerShapeCData',NaN(16,16),'PointerShapeHotSpot',[8 8]);
    crossHair = createCrossHair(hFig);
    set(hFig,'WindowButtonMotionFcn', @(s,e) updateCrossHair(hFig, crossHair));

    uicontrol(hFig,'Style','text','String','Direction:','Units','normalized', ...
        'Position',[0.02 0.115 0.07 0.035],'BackgroundColor','w','FontSize',10);
    hDir = uicontrol(hFig,'Style','popupmenu','String',{'Left to Right','Right to Left'}, ...
        'Units','normalized','Position',[0.09 0.115 0.14 0.045],'FontSize',10);

    uicontrol(hFig,'Style','pushbutton','String','< Prev','Units','normalized', ...
        'Position',[0.02 0.04 0.07 0.05],'Callback',@(s,e) changeFrame(-1));
    uicontrol(hFig,'Style','pushbutton','String','Next >','Units','normalized', ...
        'Position',[0.10 0.04 0.07 0.05],'Callback',@(s,e) changeFrame(1));
    uicontrol(hFig,'Style','pushbutton','String','<< -10','Units','normalized', ...
        'Position',[0.18 0.04 0.07 0.05],'Callback',@(s,e) changeFrame(-10));
    uicontrol(hFig,'Style','pushbutton','String','+10 >>','Units','normalized', ...
        'Position',[0.26 0.04 0.07 0.05],'Callback',@(s,e) changeFrame(10));
    uicontrol(hFig,'Style','pushbutton','String','Set Start','Units','normalized', ...
        'Position',[0.36 0.04 0.10 0.05],'Callback',@cbSetStart);
    uicontrol(hFig,'Style','pushbutton','String','Set End','Units','normalized', ...
        'Position',[0.47 0.04 0.10 0.05],'Callback',@cbSetEnd);
    uicontrol(hFig,'Style','pushbutton','String','Calibrate Width (2 clicks)', ...
        'Units','normalized','Position',[0.58 0.04 0.18 0.05],'Callback',@cbCalibrate);
    uicontrol(hFig,'Style','pushbutton','String','DONE','Units','normalized', ...
        'Position',[0.86 0.04 0.10 0.05],'FontWeight','bold','Callback',@cbDone);

    hStatus = uicontrol(hFig,'Style','text','Units','normalized', ...
        'Position',[0.36 0.105 0.60 0.04],'BackgroundColor','w','FontSize',9, ...
        'HorizontalAlignment','left','String','');

    set(hImg,'ButtonDownFcn',@cbClick,'HitTest','on','PickableParts','all');
    set(hAx,'ButtonDownFcn',@cbClick);

    refreshStatus();
    uiwait(hFig);

    if cancelled || ~doneFlag
        if ishandle(hFig), delete(hFig); end
        return;
    end

    if get(hDir,'Value') == 1
        setup.propagationDirection = 'LtoR'; setup.scanDir = -1;
    else
        setup.propagationDirection = 'RtoL'; setup.scanDir = +1;
    end
    setup.calibFrame      = calibFrame;
    setup.yTop            = min(yTop, yBottom);
    setup.yBottom         = max(yTop, yBottom);
    setup.pixelHeight     = abs(yBottom - yTop);
    setup.yRows           = round(setup.yTop):round(setup.yBottom);
    setup.yRows = setup.yRows(setup.yRows >= 1 & setup.yRows <= video.Height);
    setup.chamberWidth_in = chamberWidth_in;
    setup.mperpix         = (chamberWidth_in * 0.0254) / setup.pixelHeight;
    setup.startFrame      = startFrame;
    setup.endFrame        = endFrame;

    if ishandle(hFig), delete(hFig); end

    % ---------- nested callbacks ----------
    function changeFrame(d)
        frameNumber = max(1, min(totalFrames, frameNumber + d));
        set(hImg,'CData', read(video, frameNumber));
        drawnow limitrate;
        refreshStatus();
    end
    function cbSetStart(~,~), startFrame = frameNumber; refreshStatus(); end
    function cbSetEnd(~,~),   endFrame   = frameNumber; refreshStatus(); end
    function cbCalibrate(~,~)
        calibMode = true; calibClicks = [];
        delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
        set(hStatus,'String','CALIBRATE: click the TOP wall, then the BOTTOM wall.');
    end
    function cbClick(~,~)
        if ~calibMode, return; end
        if ~strcmp(get(hFig,'SelectionType'),'normal'), return; end
        cp = get(hAx,'CurrentPoint');
        yClick = cp(1,2);
        calibClicks(end+1) = yClick; %#ok<AGROW>
        hCalibLines(end+1) = plot(hAx, get(hAx,'XLim'), [yClick yClick], ...
            'y-', 'LineWidth', 1.2, 'HitTest','off','PickableParts','none'); %#ok<AGROW>
        if numel(calibClicks) == 2
            calibMode = false;
            yTop = calibClicks(1); yBottom = calibClicks(2);
            calibFrame = frameNumber;
            answer = inputdlg('Actual chamber width (inches):','Chamber Width', ...
                [1 40], {'2'});
            if isempty(answer)
                w = NaN;
            else
                w = str2double(answer{1});
            end
            if ~isfinite(w) || w <= 0
                yTop = []; yBottom = []; calibFrame = [];
                delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
                set(hStatus,'String','Calibration cancelled — click Calibrate again.');
            else
                chamberWidth_in = w;
            end
            refreshStatus();
        end
    end
    function cbDone(~,~)
        if isempty(yTop) || isempty(chamberWidth_in)
            set(hStatus,'String','ERROR: calibrate width first.'); return;
        end
        if abs(yBottom - yTop) < 1
            set(hStatus,'String','ERROR: calibration clicks too close — recalibrate.'); return;
        end
        if isempty(startFrame) || isempty(endFrame)
            set(hStatus,'String','ERROR: set start and end frames.'); return;
        end
        if startFrame > endFrame
            set(hStatus,'String','ERROR: start frame must be <= end frame.'); return;
        end
        doneFlag = true; uiresume(hFig);
    end
    function cbClose(~,~), cancelled = true; doneFlag = false; uiresume(hFig); end
    function refreshStatus()
        set(hStatus,'String', sprintf( ...
            'Frame %d/%d  |  Start: %s  End: %s  |  yTop: %s  yBot: %s  Width(in): %s', ...
            frameNumber, totalFrames, num2str(startFrame), num2str(endFrame), ...
            num2str(yTop), num2str(yBottom), num2str(chamberWidth_in)));
    end

    % ---------- crosshair helpers (adapted from wave_speed_gui_v16) ----------
    function ch = createCrossHair(fig)
        for k = 1:4
            ch(k) = uicontrol(fig,'Style','text','Visible','off','Units','pixels', ...
                'HandleVisibility','off','HitTest','off','BackgroundColor',[0 1 0], ...
                'Enable','inactive'); %#ok<AGROW>
        end
    end
    function updateCrossHair(fig, ch)
        gap = 3;
        cp = hgconvertunits(fig, [fig.CurrentPoint 0 0], fig.Units, 'pixels', fig);
        cp = cp(1:2);
        figPos = hgconvertunits(fig, fig.Position, fig.Units, 'pixels', fig.Parent);
        figW = figPos(3); figH = figPos(4);
        if cp(1) < gap || cp(2) < gap || cp(1) > figW-gap || cp(2) > figH-gap
            set(ch,'Visible','off'); return;
        end
        set(ch,'Visible','on'); thickness = 1;
        set(ch(1),'Position',[0, cp(2), max(1, cp(1)-gap), thickness]);
        set(ch(2),'Position',[cp(1)+gap, cp(2), max(1, figW-cp(1)-gap), thickness]);
        set(ch(3),'Position',[cp(1), 0, thickness, max(1, cp(2)-gap)]);
        set(ch(4),'Position',[cp(1), cp(2)+gap, thickness, max(1, figH-cp(2)-gap)]);
    end
end
