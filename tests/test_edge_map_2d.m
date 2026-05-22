function tests = test_edge_map_2d
tests = functiontests(localfunctions);
end

function test_sizes_and_finds_vertical_step(t)
    img = zeros(20, 40); img(:, 21:end) = 100;   % vertical step between col 20 and 21
    [Gx, Gmag, E] = edge_map_2d(img, struct('gaussSigma',1));
    verifyEqual(t, size(Gx), size(img));
    verifyEqual(t, size(Gmag), size(img));
    verifyEqual(t, size(E), size(img));
    % strongest gradient column is near the step
    [~, pk] = max(sum(Gmag,1));
    verifyTrue(t, abs(pk - 20.5) <= 2);
    % Canny marks edges near the step
    verifyTrue(t, any(E(:)));
    verifyTrue(t, any(any(E(:, 18:23))));
end

function test_default_params_run(t)
    img = rand(15, 15) * 50;
    [Gx, Gmag, E] = edge_map_2d(img);   % no params -> defaults
    verifyEqual(t, size(Gx), size(img));
    verifyTrue(t, islogical(E));
    verifyTrue(t, all(Gmag(:) >= 0));
end
