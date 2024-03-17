const std = @import("std");
const WINAPI = std.os.windows.WINAPI;

const F = f32;
const V3 = @Vector(3,F);
const sens = 16.0 * std.math.pi / 10800.0;

var mouse_grab = false;
var mouse_move = @Vector(2,i16){ 0, 0 };

var cube_state = Quat {
    .i = 6.0 * @sqrt(0.25 - 0.25/@sqrt(3.0)),
    .j = 0,
    .k = 6.0 * @sqrt(0.25 - 0.25/@sqrt(3.0)),
    .l = 6.0 * @sqrt(0.50 + 0.50/@sqrt(3.0)),
};

const cube_vertices = .{
    .{-1,-1,-1}, // 0
    .{-1,-1, 1}, // 1
    .{-1, 1,-1}, // 2
    .{-1, 1, 1}, // 3
    .{ 1,-1,-1}, // 4
    .{ 1,-1, 1}, // 5
    .{ 1, 1,-1}, // 6
    .{ 1, 1, 1}, // 7
};

const cube_faces = .{
    .{7,6,4,5}, // R
    .{7,6,2,3}, // G
    .{0,1,5,4}, // Y
    .{1,3,7,5}, // B
    .{0,1,3,2}, // M
    .{6,4,0,2}, // C
};

pub fn main() void {
    const hInstance = win32.GetModuleHandleA(null) orelse return;
    const atom = win32.RegisterClassExA(&.{
        .lpfnWndProc = wndProc,
        .hInstance = hInstance,
        .hCursor = win32.LoadCursorA(null, @ptrFromInt(32512)),
        .lpszClassName = "Window",
    });

    if (atom == 0) return;

    const hwnd = win32.CreateWindowExA(
        0,
        @ptrFromInt(@as(usize, @intCast(atom))),
        "Rotating Cube",
        win32.WS_VISIBLE | win32.WS_SYSMENU | win32.WS_CAPTION | win32.WS_THICKFRAME,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        null,
        null,
        null,
        null,
    ) orelse return;

    if (!graphic_context.init(hwnd)) return;
    defer graphic_context.deinit();
    
    const timer = win32.SetTimer(hwnd,1,10,onTick);
    if (0==timer) return;
    defer _ = win32.KillTimer(hwnd,timer);

    var msg: win32.MSG = undefined;
    while (win32.GetMessageA(&msg, null, 0, 0) > 0) {
        _ = win32.DispatchMessageA(&msg);
    }
}

fn wndProc(hwnd: *anyopaque, uMsg: u32, wParam: usize, lParam: isize) callconv(WINAPI) isize {
    switch (uMsg) {
        0x000F => { // WM_PAINT
            onPaint(hwnd);
            return 0;
        },
        0x0010 => { // WM_CLOSE
            _ = win32.PostQuitMessage(0);
        },
        0x0200 => { // WM_MOUSEMOVE
            const last = struct {
                var x: i16 = 0;
                var y: i16 = 0;
            };
            const pos: packed struct {x: i16, y: i16, unused: u32} = @bitCast(lParam);
            const dx = pos.x-last.x;
            const dy = pos.y-last.y;
            last.x = pos.x;
            last.y = pos.y;
            if (mouse_grab) {
                mouse_move += .{ dx, dy };
                const rx: F = @floatFromInt(dx);
                const ry: F = @floatFromInt(dy);
                if (pv(rx*rx+ry*ry)) |rr| {
                    const rad = @sqrt(rr) * sens;
                    cube_state = ( Quat {
                        .i = @sin(rad/2) * ( ry) / @sqrt(rr),
                        .j = @sin(rad/2) * (-rx) / @sqrt(rr),
                        .k = 0,
                        .l = @cos(rad/2),
                    } ).mul(cube_state);
                    _ = win32.InvalidateRect(hwnd,null,1);
                }
            }
        },
        0x0201 => { // WM_LBUTTONDOWN
            mouse_grab = true;
            _ = win32.SetCapture(hwnd);
        },
        0x0202 => { // WM_LBUTTONUP
            mouse_grab = false;
            _ = win32.ReleaseCapture();
        },
        0x020A => { // WM_MOUSEWHEEL
            const inf: packed struct {key: u16, step: i16, unused: u32} = @bitCast(wParam);
            const fac = @exp2(0.5 * @as(F,@floatFromInt(inf.step)) / 120.0 / 12.0);
            cube_state.i *= fac;
            cube_state.j *= fac;
            cube_state.k *= fac;
            cube_state.l *= fac;
            _ = win32.InvalidateRect(hwnd,null,1);
        },
        0x0214 => { // WM_SIZING
            onResize(hwnd, wParam, lParam);
        },        
        else => {},
    }
    return win32.DefWindowProcA(hwnd, uMsg, wParam, lParam);
}

fn onTick(hwnd: *anyopaque, _: u32, _: usize, _: u32) callconv(WINAPI) void {
    const last = struct { 
        var t: i32 = 0; 
        var v: V3 = .{0,0,0}; 
        var a: V3 = .{0,0,0}; 
    };
    const now = win32.GetMessageTime();
    const dt = now-last.t;
    last.t = now;
    last.a = kv(16);
    if (dt==now or dt==0) return;
    const t = 0.001 * @as(F,@floatFromInt(dt));
    if (mouse_grab) {
        const mx: F = @floatFromInt(mouse_move[0]);
        const my: F = @floatFromInt(mouse_move[1]);
        mouse_move = .{0,0};
        last.v = .{
            my * sens / 2 / t, 
           -mx * sens / 2 / t,
            0,
        };
    } else {
        const f0, const f1, const f2 = ev(t,3);
        const d = last.v*@as(V3,@splat(f1)) + last.a*@as(V3,@splat(f2));
        last.v  = last.v*@as(V3,@splat(f0)) + last.a*@as(V3,@splat(f1));
        if (pv(d[0]*d[0]+d[1]*d[1]+d[2]*d[2])) |rr| {
            const arg = @sqrt(rr);
            cube_state = ( Quat {
                .i = @sin(arg)*d[0]/arg,
                .j = @sin(arg)*d[1]/arg,
                .k = @sin(arg)*d[2]/arg,
                .l = @cos(arg),
            } ).mul(cube_state);
            _ = win32.InvalidateRect(hwnd,null,1);
        }
    }
}

fn onPaint(hwnd: *anyopaque) void {
    var info: win32.PAINTSTRUCT = undefined;
    const hDC = win32.BeginPaint(hwnd, &info) orelse return;
    defer _ = win32.EndPaint(hwnd, &info);
    
    var rect: std.os.windows.RECT = undefined;
    if (0==win32.GetClientRect(hwnd, &rect)) return;
    const w = rect.right-rect.left;
    const h = rect.bottom-rect.top;
    const x0 = @divTrunc(w,2);
    const y0 = @divTrunc(h,2);

    // clear bitmap to black or create one if absent
    const ctx = graphic_context; 
    if (ctx.bitmap) |_| {
        _ = win32.BitBlt(ctx.back_dc, 0, 0, w, h, ctx.back_dc, 0, 0, 0x42); // BLACKNESS
    } else { 
        const bmp = win32.CreateCompatibleBitmap(hDC,w,h) orelse return; 
        _ = win32.SelectObject(ctx.back_dc, bmp);
        ctx.bitmap = bmp; 
    }
    
    // transform the eight corner vertices
    const m = cube_state.asMatrix();
    const verts = .{
        mv(F, m, cube_vertices[0]),
        mv(F, m, cube_vertices[1]),
        mv(F, m, cube_vertices[2]),
        mv(F, m, cube_vertices[3]),
        mv(F, m, cube_vertices[4]),
        mv(F, m, cube_vertices[5]),
        mv(F, m, cube_vertices[6]),
        mv(F, m, cube_vertices[7]),
    };

    // calculate and draw visible faces
    inline for (cube_faces, 1..) |face, c| {
        const p0 = verts[face[0]];
        const p1 = verts[face[1]];
        const p2 = verts[face[2]];
        const p3 = verts[face[3]];
        const frontfacing = (p0[2]+p1[2]+p2[2]+p3[2]<0);        
        _ = win32.SelectObject(ctx.back_dc, if (frontfacing) ctx.white_pen else ctx.null_pen);
        _ = win32.SelectObject(ctx.back_dc, if (frontfacing) ctx.dc_brush  else ctx.null_brush);
        _ = win32.SetDCBrushColor(ctx.back_dc, ( c&1 | ((c&2)>>1)<<8 | ((c&4)>>2)<<16 )*255);
        _ = win32.Polygon(ctx.back_dc, &[_]std.os.windows.POINT{
            .{.x=x0+@as(i16,@intFromFloat(p0[0])), .y=y0+@as(i16,@intFromFloat(p0[1]))},
            .{.x=x0+@as(i16,@intFromFloat(p1[0])), .y=y0+@as(i16,@intFromFloat(p1[1]))},
            .{.x=x0+@as(i16,@intFromFloat(p2[0])), .y=y0+@as(i16,@intFromFloat(p2[1]))},
            .{.x=x0+@as(i16,@intFromFloat(p3[0])), .y=y0+@as(i16,@intFromFloat(p3[1]))},
        }, 4);
    }

    // draw annotation text
    {
        var str = "drag, I, J, K, L, O, U to rotate\nscroll to zoom".*;
        var rec = std.os.windows.RECT{.left=0,.top=0,.right=0,.bottom=0};
        const b = win32.SetBkMode(ctx.back_dc, 1);
        defer _ = win32.SetBkMode(ctx.back_dc, b);
        const t = win32.SetTextColor(ctx.back_dc, 0xFFFFFF);
        defer _ = win32.SetTextColor(ctx.back_dc, t);
        _ = win32.DrawTextA(ctx.back_dc, &str, -1, &rec, 0x100);
    }

    // copy to the actual window buffer
    _ = win32.BitBlt(hDC, 0, 0, w, h, ctx.back_dc, 0, 0, 0x00CC0020); // SRCCOPY
}

fn onResize(hwnd: *anyopaque, wParam: usize, lParam: isize) void {
    if (wParam<9) {
        const rect: *std.os.windows.RECT = @ptrFromInt(@as(usize,@bitCast(lParam)));
        const w, const h = .{ @max(200,rect.right-rect.left), @max(200,rect.bottom-rect.top) };
        const op = ([9][4]bool{
            .{false,false,false,false}, // none
            .{ true,false,false,false}, // left edge
            .{false,false, true,false}, // right edge
            .{false, true,false,false}, // top edge
            .{ true, true,false,false}, // top left corner
            .{false, true, true,false}, // top right corner
            .{false,false,false, true}, // bottom edge
            .{ true,false,false, true}, // bottom left corner
            .{false,false, true, true}, // bottom right corner
        })[wParam];
        rect.left   = if(op[0]) rect.right-w  else rect.left;
        rect.top    = if(op[1]) rect.bottom-h else rect.top;
        rect.right  = if(op[2]) rect.left+w   else rect.right;
        rect.bottom = if(op[3]) rect.top+h    else rect.bottom;
    }
    if (graphic_context.bitmap) |bmp| _ = win32.DeleteObject(bmp);
    graphic_context.bitmap = null;
    _ = win32.InvalidateRect(hwnd,null,1);
}

fn pv(x: F) ?F {
    return if(x>0) x else null;
}

fn ev(t: F, u: F) [3]F {
    const f0 = if (u>0) @exp(-t*u) else 1;
    const f1 = if (u>0) (1 - f0)/u else t;
    const f2 = if (u>0) (t - f1)/u else t*t*0.5;
    return .{f0,f1,f2};
}

fn mv(comptime T: type, m: [9]T, v: [3]T) [3]T {
    return .{
        m[0]*v[0] + m[1]*v[1] + m[2]*v[2],
        m[3]*v[0] + m[4]*v[1] + m[5]*v[2],
        m[6]*v[0] + m[7]*v[1] + m[8]*v[2],
    };
}

fn kv(scale: F) [3]F {
    const i: F = if (0!=win32.GetAsyncKeyState(0x49)) 1 else 0;
    const j: F = if (0!=win32.GetAsyncKeyState(0x4A)) 1 else 0;
    const k: F = if (0!=win32.GetAsyncKeyState(0x4B)) 1 else 0;
    const l: F = if (0!=win32.GetAsyncKeyState(0x4C)) 1 else 0;
    const o: F = if (0!=win32.GetAsyncKeyState(0x4F)) 1 else 0;
    const u: F = if (0!=win32.GetAsyncKeyState(0x55)) 1 else 0;
    return .{
        scale*(k-i),
        scale*(j-l),
        scale*(o-u),
    };
}

const Quat = struct {
    i: F = 0, j: F = 0, k: F = 0, l: F = 1,
    fn mul(a: Quat, b: Quat) Quat {
        const ii, const ij, const ik, const il,
        const ji, const jj, const jk, const jl,
        const ki, const kj, const kk, const kl,
        const li, const lj, const lk, const ll = outer(a,b);       
        return .{ 
            .i = li-kj+jk+il, 
            .j = lj+ki+jl-ik, 
            .k = lk+kl-ji+ij, 
            .l = ll-kk-jj-ii,
        };
    }
    fn outer(a: Quat, b: Quat) [16]F {
        return .{
            a.i*b.i,a.i*b.j,a.i*b.k,a.i*b.l,
            a.j*b.i,a.j*b.j,a.j*b.k,a.j*b.l,
            a.k*b.i,a.k*b.j,a.k*b.k,a.k*b.l,
            a.l*b.i,a.l*b.j,a.l*b.k,a.l*b.l,
        };
    }
    fn asMatrix(q: Quat) [9]F {
        const ii, const ij, const ik, const il,
        const ji, const jj, const jk, const jl,
        const ki, const kj, const kk, const kl,
        const li, const lj, const lk, const ll = outer(q,q);
        return .{
            ll+ii-(jj+kk), ij+ji-(kl+lk), ki+ik+(lj+jl),
            ij+ji+(kl+lk), ll+jj-(kk+ii), jk+kj-(li+il),
            ki+ik-(lj+jl), jk+kj+(li+il), ll+kk-(ii+jj),
        };
    }
};

const graphic_context = struct {
    var back_dc: std.os.windows.HDC = undefined;
    var white_brush: *anyopaque = undefined;
    var black_brush: *anyopaque = undefined;
    var null_brush: *anyopaque = undefined;
    var white_pen: *anyopaque = undefined;
    var black_pen: *anyopaque = undefined;
    var null_pen: *anyopaque = undefined;
    var dc_brush: *anyopaque = undefined;
    var dc_pen: *anyopaque = undefined;
    var bitmap: ?*anyopaque = null;
    fn init(hwnd: *anyopaque) bool {
        back_dc = _: {
            const hDC = win32.GetDC(hwnd) orelse return false;
            defer _ = win32.ReleaseDC(hwnd, hDC);
            break : _ win32.CreateCompatibleDC(hDC) orelse return false;
        };     
        white_brush = win32.GetStockObject(0) orelse return false;
        black_brush = win32.GetStockObject(4) orelse return false;
        null_brush = win32.GetStockObject(5) orelse return false;
        white_pen = win32.GetStockObject(6) orelse return false;
        black_pen = win32.GetStockObject(7) orelse return false;
        null_pen = win32.GetStockObject(8) orelse return false;
        dc_brush = win32.GetStockObject(18) orelse return false;
        dc_pen = win32.GetStockObject(19) orelse return false;
        return true;
    }
    fn deinit() void {        
        _ = win32.DeleteDC(back_dc);
    }
};

const win32 = struct {
    // WinAPI constants
    const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000)); // sign bit of an i32
    const WS_VISIBLE = 0x10000000;
    const WS_SYSMENU = 0x00080000;
    const WS_CAPTION = 0x00C00000;
    const WS_THICKFRAME = 0x00040000;

    // WinAPI typedefs
    const HDC = std.os.windows.HDC;    
    const TIMERPROC = *const fn (*anyopaque, u32, usize, u32) callconv(WINAPI) void;
    const MSG = extern struct { hWnd: ?*anyopaque, message: u32, wParam: usize, lParam: isize, time: u32, pt: std.os.windows.POINT, lPrivate: u32 };
    const WNDCLASSEXA = extern struct {
        cbSize: u32 = @sizeOf(@This()),
        style: u32 = 0,
        lpfnWndProc: *const fn (*anyopaque, u32, usize, isize) callconv(WINAPI) isize,
        cbClsExtra: i32 = 0,
        cbWndExtra: i32 = 0,
        hInstance: *anyopaque,
        hIcon: ?*anyopaque = null,
        hCursor: ?*anyopaque = null,
        hbrBackground: ?*anyopaque = null,
        lpszMenuName: ?[*:0]const u8 = null,
        lpszClassName: [*:0]const u8,
        hIconSm: ?*anyopaque = null,
    };
    const PAINTSTRUCT = extern struct {
        hdc: *anyopaque,
        fErase: i32,
        rcPaint: std.os.windows.RECT,
        fRestore: i32,
        fIncUpdate: i32,
        rgbReserved: [32]u8,
    };

    // WinAPI DLL functions
    extern "kernel32" fn GetModuleHandleA(?[*:0]const u8) callconv(WINAPI) ?*anyopaque;
    extern "user32" fn GetMessageA(*MSG, ?*anyopaque, u32, u32) callconv(WINAPI) i32;
    extern "user32" fn DispatchMessageA(*MSG) callconv(WINAPI) isize;
    extern "user32" fn DefWindowProcA(*anyopaque, u32, usize, isize) callconv(WINAPI) isize;
    extern "user32" fn PostQuitMessage(i32) callconv(WINAPI) void;
    extern "user32" fn LoadCursorA(?*anyopaque, ?*anyopaque) callconv(WINAPI) ?*anyopaque;
    extern "user32" fn RegisterClassExA(*const WNDCLASSEXA) callconv(WINAPI) u16;
    extern "user32" fn AdjustWindowRect(*std.os.windows.RECT, u32, i32) callconv(WINAPI) i32;
    extern "user32" fn GetClientRect(*anyopaque, *const std.os.windows.RECT) callconv(WINAPI) i32;
    extern "user32" fn InvalidateRect(*anyopaque, ?*anyopaque, i32) callconv(WINAPI) i32;
    extern "user32" fn CreateWindowExA(
        u32, // extended style
        ?*anyopaque, // class name/class atom
        ?[*:0]const u8, // window name
        u32, // basic style
        i32,i32,i32,i32, // x,y,w,h
        ?*anyopaque, // parent
        ?*anyopaque, // menu
        ?*anyopaque, // hInstance
        ?*anyopaque, // info to pass to WM_CREATE callback inside wndproc
    ) callconv(WINAPI) ?*anyopaque;
    extern "user32" fn BeginPaint(*anyopaque, *PAINTSTRUCT) callconv(WINAPI) ?HDC;
    extern "user32" fn EndPaint(*anyopaque, *const PAINTSTRUCT) callconv(WINAPI) i32;
    extern "user32" fn FillRect(HDC, *const std.os.windows.RECT, *anyopaque) callconv(WINAPI) i32;
    extern "user32" fn GetDC(?*anyopaque) callconv(WINAPI) ?HDC;
    extern "user32" fn ReleaseDC(?*anyopaque, HDC) i32;
    extern "user32" fn SetTimer(?*anyopaque, usize, u32, ?TIMERPROC) callconv(WINAPI) usize;
    extern "user32" fn KillTimer(?*anyopaque, usize) callconv(WINAPI) i32;
    extern "user32" fn SetCapture(*anyopaque) callconv(WINAPI) ?*anyopaque;
    extern "user32" fn ReleaseCapture() callconv(WINAPI) i32;
    extern "user32" fn GetMessageTime() callconv(WINAPI) i32;
    extern "user32" fn GetAsyncKeyState(i32) callconv(WINAPI) i16;
    extern "user32" fn DrawTextA(HDC, [*:0]u8, i32, *std.os.windows.RECT, u32) callconv(WINAPI) i32;
    extern "gdi32" fn DeleteDC(HDC) callconv(WINAPI) i32;
    extern "gdi32" fn DeleteObject(*anyopaque) callconv(WINAPI) i32;
    extern "gdi32" fn SelectObject(HDC, *anyopaque) callconv(WINAPI) ?*anyopaque;
    extern "gdi32" fn GetStockObject(i32) callconv(WINAPI) ?*anyopaque;
    extern "gdi32" fn CreateCompatibleBitmap(HDC, i32, i32) callconv(WINAPI) ?*anyopaque;
    extern "gdi32" fn CreateCompatibleDC(?HDC) callconv(WINAPI) ?HDC;
    extern "gdi32" fn BitBlt(HDC, i32, i32, i32, i32, HDC, i32, i32, u32) callconv(WINAPI) i32;
    extern "gdi32" fn Polygon(HDC, [*]const std.os.windows.POINT, i32) callconv(WINAPI) i32;
    extern "gdi32" fn SetBkMode(HDC, i32) callconv(WINAPI) i32;
    extern "gdi32" fn SetTextColor(HDC, u32) callconv(WINAPI) u32;
    extern "gdi32" fn SetDCPenColor(HDC, u32) callconv(WINAPI) u32;
    extern "gdi32" fn SetDCBrushColor(HDC, u32) callconv(WINAPI) u32;
};