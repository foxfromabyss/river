// This file is part of river, a dynamic tiling wayland compositor.
//
// Copyright 2020 The River Developers
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const Self = @This();

const std = @import("std");
const wlr = @import("wlroots");
const wl = @import("wayland").server.wl;

const util = @import("util.zig");

const Box = @import("Box.zig");
const Output = @import("Output.zig");

const log = std.log.scoped(.server);

/// The output this popup is displayed on.
output: *Output,

/// Box of the parent of this popup tree. Needed to unconstrain child popups.
parent_box: *const Box,

/// The corresponding wlroots object
wlr_xdg_popup: *wlr.XdgPopup,

destroy: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleDestroy),
new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),

pub fn init(self: *Self, output: *Output, parent_box: *const Box, wlr_xdg_popup: *wlr.XdgPopup) void {
    self.* = .{
        .output = output,
        .parent_box = parent_box,
        .wlr_xdg_popup = wlr_xdg_popup,
    };

    // The output box relative to the parent of the popup
    const output_dimensions = output.getEffectiveResolution();
    var box = wlr.Box{
        .x = -parent_box.x,
        .y = -parent_box.y,
        .width = @intCast(c_int, output_dimensions.width),
        .height = @intCast(c_int, output_dimensions.height),
    };
    wlr_xdg_popup.unconstrainFromBox(&box);

    wlr_xdg_popup.base.events.destroy.add(&self.destroy);
    wlr_xdg_popup.base.events.new_popup.add(&self.new_popup);
}

fn handleDestroy(listener: *wl.Listener(*wlr.XdgSurface), wlr_xdg_surface: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "destroy", listener);

    self.destroy.link.remove();
    self.new_popup.link.remove();

    util.gpa.destroy(self);
}

/// Called when a new xdg popup is requested by the client
fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), wlr_xdg_popup: *wlr.XdgPopup) void {
    const self = @fieldParentPtr(Self, "new_popup", listener);

    // This will free itself on destroy
    const xdg_popup = util.gpa.create(Self) catch {
        wlr_xdg_popup.resource.postNoMemory();
        log.crit("out of memory", .{});
        return;
    };
    xdg_popup.init(self.output, self.parent_box, wlr_xdg_popup);
}
