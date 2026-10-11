function R = vertex_R(surf)
    % Base radius near the on-axis vertex from sag ~ r^2/(2R). Uses a point at
    % ~1/4 of the surface's max radius; approximate (surface is aspheric).
    r = abs(surf(:,2));  z = surf(:,1);
    [~, iv] = min(r);  zv = z(iv);
    [~, ip] = min(abs(r - 0.25*max(r)));
    dz = abs(z(ip) - zv);
    if dz < 1e-6, R = Inf; else, R = r(ip)^2 / (2*dz); end
end
