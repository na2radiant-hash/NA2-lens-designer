function a = wrapTo180(a)
%WRAPTO180  Wrap angle(s) in degrees to (-180, 180].
    a = mod(a + 180, 360) - 180;
end
