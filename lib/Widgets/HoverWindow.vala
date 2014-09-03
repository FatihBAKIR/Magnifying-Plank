//
//  Copyright (C) 2011-2012 Robert Dyer, Rico Tzschichholz
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Cairo;
using Gdk;
using Gtk;

namespace Plank.Widgets
{
	/**
	 * A hover window that shows labels for dock items.
	 * This window floats outside (but near) the dock.
	 */
	public class HoverWindow : Gtk.Window
	{
		const int PADDING = 10;
		
		Gtk.Box box;
		Gtk.Label label;
		
		public HoverWindow ()
		{
			GLib.Object (type: Gtk.WindowType.POPUP, type_hint: WindowTypeHint.TOOLTIP);
		}
		
		construct
		{
			app_paintable = true;
			resizable = false;
			
			unowned Screen screen = get_screen ();
			set_visual (screen.get_rgba_visual () ?? screen.get_system_visual ());
			
			get_style_context ().add_class (Gtk.STYLE_CLASS_TOOLTIP);
			
			box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			box.set_margin_left (6);
			box.set_margin_right (6);
			box.set_margin_top (6);
			box.set_margin_bottom (6);
			add (box);
			box.show ();
			
			label = new Gtk.Label (null);
			label.set_line_wrap (true);
			box.pack_start (label, false, false, 0);
		}
		
		/**
		 * Shows and centers the window according to the x/y location specified
		 * while accounting the dock's position.
		 *
		 * @param x the x location
		 * @param y the y location
		 * @param position the dock's position
		 */
		public void show_at (int x, int y, PositionType position, int size)
		{
			unowned Screen screen = get_screen ();
			Gdk.Rectangle monitor;
			screen.get_monitor_geometry (screen.get_monitor_at_point (x, y), out monitor);
			
			// realize and show the window early to have current allocation-dimensions
			// this is also needed for being able to move override-redirect windows
			// on mutter-derived window-managers
			show ();
			
			var width = get_allocated_width ();
			var height = get_allocated_height ();
			
			switch (position) {
			case PositionType.BOTTOM:
				x = x - width / 2;
				y = y - height - PADDING - size * 3 / 4;
				break;
			case PositionType.TOP:
				x = x - width / 2;
				y = y + PADDING;
				break;
			case PositionType.LEFT:
				x = x + PADDING;
				y = y - height / 2;
				break;
			case PositionType.RIGHT:
				x = x - width - PADDING;
				y = y - height / 2;
				break;
			}
			
			x = int.max (monitor.x, int.min (x, monitor.x + monitor.width - width));
			y = int.max (monitor.y, int.min (y, monitor.y + monitor.height - height));
			
			move (x, y);
		}
		
		/**
		 * Set the tooltip-text to show
		 *
		 * @param text the text to show
		 */
		public void set_text (string text)
		{
			label.set_text (text);
			if (text != null)
				label.show ();
			else
				label.hide ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override bool draw (Cairo.Context cr)
		{
			var width = get_allocated_width ();
			var height = get_allocated_height ();
			var context = get_style_context ();
			
			if (is_composited ()) {
				cr.save ();
				cr.set_source_rgba (0, 0, 0, 0);
				cr.set_operator (Cairo.Operator.SOURCE);
				cr.paint ();
				cr.restore ();
				
#if VALA_0_24
				shape_combine_region (null);
#else
				gtk_widget_shape_combine_region (this, null);
#endif
				
				context.render_background (cr, 0, 0, width, height);
				context.render_frame (cr, 0, 0, width, height);  
			} else {
				var surface = get_window ().create_similar_surface (Cairo.Content.COLOR_ALPHA, width, height);
				var compat_cr = new Cairo.Context (surface);
				
				context.render_background (compat_cr, 0, 0, width, height);
				context.render_frame (compat_cr, 0, 0, width, height);  
				
				var region = Gdk.cairo_region_create_from_surface (surface);
				shape_combine_region (region);
			}
			
			return base.draw (cr);
		}
	}
}
