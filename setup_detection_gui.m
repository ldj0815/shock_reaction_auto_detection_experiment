function setup = setup_detection_gui(src, defaultFrame)
%SETUP_DETECTION_GUI Direction, detector mode, calibration, background, ROI, frame range.
%   setup fields (or [] if cancelled):
%     propagationDirection ('LtoR'|'RtoL'), scanDir (+1|-1),
%     detectorMode ('band2d'|'step1d'),
%     calibFrame, yTop, yBottom, pixelHeight, yRows, chamberWidth_in, mperpix,
%     backgroundFrame, roiMask (HxW logical), roiClipLeft, roiClipRight,
%     startFrame, endFrame
    setup = [];
    totalFrames = src.NumFrames;
    if nargin < 2 || isempty(defaultFrame)
        defaultFrame = round(totalFrames/2);
    end
    frameNumber = max(1, min(defaultFrame, totalFrames));

    yTop = []; yBottom = []; calibFrame = [];
    startFrame = []; endFrame = []; chamberWidth_in = []; backIdx = [];
    roiAuto = []; roiClipLeft = []; roiClipRight = [];
    calibMode = false; calibClicks = []; roiPickMode = '';
    doneFlag = false; cancelled = false;
    hCalibLines = gobjects(0); hRoiLines = gobjects(0);

    hFig = figure('Name','Detection Setup','NumberTitle','off', ...
        'WindowState','maximized','Color','w','CloseRequestFcn',@cbClose);
    hAx = axes('Parent',hFig,'Units','normalized','Position',[0.02 0.22 0.96 0.76]);
    axis(hAx,'off');
    hImg = imshow(dat_frame(src,frameNumber), [], 'Parent', hAx);
    hold(hAx,'on');

    set(hFig,'Pointer','custom','PointerShapeCData',NaN(16,16),'PointerShapeHotSpot',[8 8]);
    crossHair = createCrossHair(hFig);
    set(hFig,'WindowButtonMotionFcn', @(s,e) updateCrossHair(hFig, crossHair));

    uicontrol(hFig,'Style','text','String','Direction:','Units','normalized', ...
        'Position',[0.02 0.135 0.07 0.035],'BackgroundColor','w','FontSize',10);
    hDir = uicontrol(hFig,'Style','popupmenu','String',{'Left to Right','Right to Left'}, ...
        'Units','normalized','Position',[0.09 0.135 0.12 0.045],'FontSize',10);
    uicontrol(hFig,'Style','text','String','Detector:','Units','normalized', ...
        'Position',[0.23 0.135 0.07 0.035],'BackgroundColor','w','FontSize',10);
    hMode = uicontrol(hFig,'Style','popupmenu','String',{'2D bands','1D step-height'}, ...
        'Units','normalized','Position',[0.30 0.135 0.12 0.045],'FontSize',10);

    uicontrol(hFig,'Style','pushbutton','String','< Prev','Units','normalized', ...
        'Position',[0.02 0.06 0.05 0.05],'Callback',@(s,e) changeFrame(-1));
    uicontrol(hFig,'Style','pushbutton','String','Next >','Units','normalized', ...
        'Position',[0.08 0.06 0.05 0.05],'Callback',@(s,e) changeFrame(1));
    uicontrol(hFig,'Style','pushbutton','String','<< -10','Units','normalized', ...
        'Position',[0.14 0.06 0.05 0.05],'Callback',@(s,e) changeFrame(-10));
    uicontrol(hFig,'Style','pushbutton','String','+10 >>','Units','normalized', ...
        'Position',[0.20 0.06 0.05 0.05],'Callback',@(s,e) changeFrame(10));
    uicontrol(hFig,'Style','pushbutton','String','Set Start','Units','normalized', ...
        'Position',[0.27 0.06 0.07 0.05],'Callback',@cbSetStart);
    uicontrol(hFig,'Style','pushbutton','String','Set End','Units','normalized', ...
        'Position',[0.35 0.06 0.07 0.05],'Callback',@cbSetEnd);
    uicontrol(hFig,'Style','pushbutton','String','Set Background','Units','normalized', ...
        'Position',[0.43 0.06 0.10 0.05],'Callback',@cbSetBackground);
    uicontrol(hFig,'Style','pushbutton','String','Calibrate Width','Units','normalized', ...
        'Position',[0.54 0.06 0.10 0.05],'Callback',@cbCalibrate);
    uicontrol(hFig,'Style','pushbutton','String','Set ROI Left','Units','normalized', ...
        'Position',[0.65 0.06 0.09 0.05],'Callback',@(s,e) cbSetRoi('left'));
    uicontrol(hFig,'Style','pushbutton','String','Set ROI Right','Units','normalized', ...
        'Position',[0.75 0.06 0.09 0.05],'Callback',@(s,e) cbSetRoi('right'));
    uicontrol(hFig,'Style','pushbutton','String','DONE','Units','normalized', ...
        'Position',[0.86 0.06 0.10 0.05],'FontWeight','bold','Callback',@cbDone);

    hStatus = uicontrol(hFig,'Style','text','Units','normalized', ...
        'Position',[0.02 0.005 0.94 0.045],'BackgroundColor','w','FontSize',9, ...
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
    if get(hMode,'Value') == 1
        setup.detectorMode = 'band2d';
    else
        setup.detectorMode = 'step1d';
    end
    setup.calibFrame      = calibFrame;
    setup.yTop            = min(yTop, yBottom);
    setup.yBottom         = max(yTop, yBottom);
    setup.pixelHeight     = abs(yBottom - yTop);
    setup.yRows           = round(setup.yTop):round(setup.yBottom);
    setup.yRows           = setup.yRows(setup.yRows >= 1 & setup.yRows <= src.Height);
    setup.chamberWidth_in = chamberWidth_in;
    setup.mperpix         = (chamberWidth_in * 0.0254) / setup.pixelHeight;
    setup.backgroundFrame = backIdx;
    setup.startFrame      = startFrame;
    setup.endFrame        = endFrame;
    colMask = false(1, src.Width);
    colMask(round(roiClipLeft):round(roiClipRight)) = true;
    setup.roiMask = roiAuto & repmat(colMask, src.Height, 1);
    setup.roiClipLeft  = round(roiClipLeft);
    setup.roiClipRight = round(roiClipRight);

    if ishandle(hFig), delete(hFig); end

    function changeFrame(d)
        frameNumber = max(1, min(totalFrames, frameNumber + d));
        fr = dat_frame(src, frameNumber);
        set(hImg, 'CData', fr);
        lo = min(fr(:)); hi = max(fr(:));
        if hi <= lo, hi = lo + 1; end
        set(hAx, 'CLim', [lo hi]);
        drawnow limitrate;
        refreshStatus();
    end
    function cbSetStart(~,~), startFrame = frameNumber; refreshStatus(); end
    function cbSetEnd(~,~),   endFrame   = frameNumber; refreshStatus(); end
    function cbSetBackground(~,~)
        backIdx = frameNumber;
        backRef = dat_frame(src, backIdx);
        try
            roiAuto = auto_roi_mask(backRef);
        catch
            roiAuto = true(src.Height, src.Width);
        end
        cols = find(any(roiAuto, 1));
        if isempty(cols)
            roiClipLeft = 1; roiClipRight = src.Width;
            roiAuto = true(src.Height, src.Width);
        else
            roiClipLeft = cols(1); roiClipRight = cols(end);
        end
        drawRoiLines();
        refreshStatus();
    end
    function cbCalibrate(~,~)
        calibMode = true; roiPickMode = ''; calibClicks = [];
        delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
        set(hStatus,'String','CALIBRATE: click the TOP wall, then the BOTTOM wall.');
    end
    function cbSetRoi(side)
        if isempty(roiAuto)
            set(hStatus,'String','ERROR: Set Background first (auto-ROI needs it).'); return;
        end
        calibMode = false; roiPickMode = side;
        set(hStatus,'String', sprintf('Click a column to set the ROI %s boundary.', side));
    end
    function cbClick(~,~)
        if ~strcmp(get(hFig,'SelectionType'),'normal'), return; end
        if calibMode
            cp = get(hAx,'CurrentPoint'); yClick = cp(1,2);
            calibClicks(end+1) = yClick; %#ok<AGROW>
            hCalibLines(end+1) = plot(hAx, get(hAx,'XLim'), [yClick yClick], ...
                'y-', 'LineWidth', 1.2, 'HitTest','off','PickableParts','none'); %#ok<AGROW>
            if numel(calibClicks) == 2
                yTop = calibClicks(1); yBottom = calibClicks(2);
                calibFrame = frameNumber;
                answer = inputdlg('Actual chamber width (inches):','Chamber Width', ...
                    [1 40], {'2'});
                if isempty(answer), w = NaN; else, w = str2double(answer{1}); end
                if ~isfinite(w) || w <= 0
                    yTop=[]; yBottom=[]; calibFrame=[];
                    delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
                    set(hStatus,'String','Calibration cancelled — click Calibrate again.');
                else
                    chamberWidth_in = w;
                end
                calibMode = false;
                refreshStatus();
            end
            return;
        end
        if ~isempty(roiPickMode)
            cp = get(hAx,'CurrentPoint');
            xClick = max(1, min(src.Width, round(cp(1,1))));
            if strcmp(roiPickMode,'left')
                roiClipLeft = xClick;
            else
                roiClipRight = xClick;
            end
            if roiClipLeft > roiClipRight
                tmp = roiClipLeft; roiClipLeft = roiClipRight; roiClipRight = tmp;
            end
            roiPickMode = '';
            drawRoiLines();
            refreshStatus();
        end
    end
    function drawRoiLines()
        delete(hRoiLines(ishandle(hRoiLines))); hRoiLines = gobjects(0);
        if isempty(roiClipLeft) || isempty(roiClipRight), return; end
        yl = get(hAx,'YLim');
        hRoiLines(end+1) = plot(hAx, [roiClipLeft roiClipLeft], yl, ...
            'g-', 'LineWidth', 1.2, 'HitTest','off','PickableParts','none'); %#ok<AGROW>
        hRoiLines(end+1) = plot(hAx, [roiClipRight roiClipRight], yl, ...
            'g-', 'LineWidth', 1.2, 'HitTest','off','PickableParts','none'); %#ok<AGROW>
    end
    function cbDone(~,~)
        if isempty(yTop) || isempty(chamberWidth_in)
            set(hStatus,'String','ERROR: calibrate width first.'); return;
        end
        if abs(yBottom - yTop) < 1
            set(hStatus,'String','ERROR: calibration clicks too close — recalibrate.'); return;
        end
        if isempty(backIdx)
            set(hStatus,'String','ERROR: set a background frame first.'); return;
        end
        if isempty(roiAuto) || isempty(roiClipLeft) || isempty(roiClipRight)
            set(hStatus,'String','ERROR: ROI not set (re-Set Background).'); return;
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
            ['Frame %d/%d  |  Start: %s  End: %s  Bg: %s  |  yTop: %s yBot: %s  W(in): %s  ' ...
             '|  ROI cols: [%s, %s]'], ...
            frameNumber, totalFrames, num2str(startFrame), num2str(endFrame), num2str(backIdx), ...
            num2str(yTop), num2str(yBottom), num2str(chamberWidth_in), ...
            num2str(roiClipLeft), num2str(roiClipRight)));
    end

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
