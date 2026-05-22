function tests = test_load_dat_video
tests = functiontests(localfunctions);
end

function tmp = writeSyntheticDat(headerBytes, vals16)
    % vals16: uint16 row vector of the pixel payload (after the header)
    tmp = [tempname '.dat'];
    fid = fopen(tmp, 'w', 'l');
    fwrite(fid, zeros(headerBytes,1), 'uint8');     % dummy header
    fwrite(fid, uint16(vals16), 'uint16');          % little-endian payload
    fclose(fid);
end

function test_reads_dimensions_frames_and_pixels(t)
    % W=3, H=2, N=2; payload is column-major per frame
    f1 = [10 20 30 40 50 60];      % frame 1
    f2 = [110 120 130 140 150 160];% frame 2
    tmp = writeSyntheticDat(8, [f1 f2]);
    c = onCleanup(@() delete(tmp));
    fmt = struct('headerBytes',8,'width',3,'height',2);
    src = load_dat_video(tmp, fmt);
    verifyEqual(t, src.Width, 3);
    verifyEqual(t, src.Height, 2);
    verifyEqual(t, src.NumFrames, 2);
    % reshape [W H] then transpose -> frame(h,w)
    verifyEqual(t, dat_frame(src,1), [10 20 30; 40 50 60]);
    verifyEqual(t, dat_frame(src,2), [110 120 130; 140 150 160]);
end

function test_errors_on_noninteger_frame_count(t)
    f1 = [10 20 30 40 50 60];
    tmp = writeSyntheticDat(8, f1);       % only 1 frame's worth of data
    c = onCleanup(@() delete(tmp));
    fmt = struct('headerBytes',8,'width',4,'height',2);  % frame=4*2*2=16B; (20-8)/16 not integer
    verifyError(t, @() load_dat_video(tmp, fmt), 'load_dat_video:badFormat');
end

function test_dat_frame_returns_double(t)
    tmp = writeSyntheticDat(8, [1 2 3 4 5 6]);
    c = onCleanup(@() delete(tmp));
    src = load_dat_video(tmp, struct('headerBytes',8,'width',3,'height',2));
    verifyClass(t, dat_frame(src,1), 'double');
end
