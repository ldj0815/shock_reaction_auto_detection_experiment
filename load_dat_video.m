function src = load_dat_video(path, fmt)
%LOAD_DAT_VIDEO Read a raw high-speed-camera .dat into a frame source.
%   src = load_dat_video(path)        uses default format constants
%   src = load_dat_video(path, fmt)   overrides any of the format fields
%
%   fmt fields (defaults): headerBytes=6336, width=400, height=250,
%   dtype='uint16', byteOrder='l' (little-endian). NumFrames is INFERRED
%   from the file size and the function errors if it is not a positive integer.
%
%   src has fields: Width, Height, NumFrames, Data ([H x W x N] of dtype),
%   fmt, filePath. Use dat_frame(src, idx) to get a single 2-D double frame.
    if nargin < 2 || isempty(fmt), fmt = struct(); end
    d = struct('headerBytes',6336,'width',400,'height',250, ...
               'dtype','uint16','byteOrder','l');
    fn = fieldnames(d);
    for k = 1:numel(fn)
        if ~isfield(fmt, fn{k}), fmt.(fn{k}) = d.(fn{k}); end
    end

    info = dir(path);
    if isempty(info)
        error('load_dat_video:notFound', 'File not found: %s', path);
    end
    bpp = bytesPerPixel(fmt.dtype);
    frameBytes = fmt.width * fmt.height * bpp;
    nf = (info.bytes - fmt.headerBytes) / frameBytes;
    if nf <= 0 || mod(nf,1) ~= 0
        error('load_dat_video:badFormat', ...
            ['File size %d B with header %d B and frame %d B does not yield ' ...
             'an integer frame count (got %.3f).'], info.bytes, fmt.headerBytes, frameBytes, nf);
    end
    nf = round(nf);

    fid = fopen(path, 'r', fmt.byteOrder);
    if fid < 0, error('load_dat_video:open', 'Could not open %s', path); end
    closer = onCleanup(@() fclose(fid));
    fseek(fid, fmt.headerBytes, 'bof');
    raw = fread(fid, fmt.width*fmt.height*nf, [fmt.dtype '=>' fmt.dtype]);

    expected = fmt.width*fmt.height*nf;
    if numel(raw) ~= expected
        error('load_dat_video:truncated', ...
            'File truncated or unreadable: expected %d pixels, read %d.', expected, numel(raw));
    end

    A = reshape(raw, [fmt.width, fmt.height, nf]);
    A = permute(A, [2 1 3]);   % -> [H W N]

    src = struct('Width',fmt.width, 'Height',fmt.height, 'NumFrames',nf, ...
                 'Data',A, 'fmt',fmt, 'filePath',path);
end

function b = bytesPerPixel(dtype)
    switch dtype
        case {'uint8','int8'},               b = 1;
        case {'uint16','int16'},             b = 2;
        case {'uint32','int32','single'},    b = 4;
        case {'double','uint64','int64'},    b = 8;
        otherwise, error('load_dat_video:dtype', 'Unsupported dtype %s', dtype);
    end
end
