function a = wrapTo360(a)
%WRAPTO360  Wrap angle(s) in degrees to [0, 360).
    a = mod(a, 360); a(a < 0) = a(a < 0) + 360;
end
