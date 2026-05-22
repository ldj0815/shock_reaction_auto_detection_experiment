function f = dat_frame(src, idx)
%DAT_FRAME Return one frame from a load_dat_video source as a 2-D double.
%   f = dat_frame(src, idx)  ->  src.Height x src.Width double image.
    f = double(src.Data(:,:,idx));
end
