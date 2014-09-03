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

using Gdk;
using Gee;
using Gtk;

using Plank.Drawing;
using Plank.Services;
using Plank.Services.Windows;

namespace Plank.Items
{
	/**
	 * Draws a modified surface onto another newly created or given surface
	 *
	 * @param item the dock-item
	 * @param source original surface which may not be changed
	 * @param target the previously modified surface
	 * @return the modified surface or passed through target
	 */
	public delegate DockSurface DrawItemFunc (DockItem item, DockSurface source, DockSurface? target);
	
	/**
	 * What item indicator to show.
	 */
	public enum IndicatorState
	{
		/**
		 * None - no windows for this item.
		 */
		NONE,
		/**
		 * Show a single indicator - there is 1 window for this item.
		 */
		SINGLE,
		/**
		 * Show multiple indicators - there are more than 1 window for this item.
		 */
		SINGLE_PLUS
	}
	
	/**
	 * The current activity state of an item.  The item has several
	 * states to track and can be in any combination of them.
	 */
	[Flags]
	public enum ItemState
	{
		/**
		 * The item is in a normal state.
		 */
		NORMAL = 1 << 0,
		/**
		 * The item is currently active (a window in the group is focused).
		 */
		ACTIVE = 1 << 1,
		/**
		 * The item is currently urgent (a window in the group has the urgent flag).
		 */
		URGENT = 1 << 2,
		/**
		 * The item is currently moved to its new position.
		 */
		MOVE = 1 << 3
	}
	
	/**
	 * The base class for all dock items.
	 */
	public class DockItem : DockElement
	{
		/**
		 * Signal fired when the .dockitem for this item was deleted.
		 */
		public signal void deleted ();
		
		/**
		 * Signal fired when the launcher associated with the dock item changed.
		 */
		public signal void launcher_changed ();
		
		/**
		 * The dock item's provider which it is added too (if any).
		 */
		public DockItemProvider? Provider { get; set; }
		
		/**
		 * The dock item's icon.
		 */
		public string Icon { get; set; default = ""; }
		
		protected Pixbuf? ForcePixbuf { get; set; default = null; }
		
		/**
		 * The count for the dock item.
		 */
		public int64 Count { get; set; default = 0; }
		
		/**
		 * Show the item's count or not.
		 */
		public bool CountVisible { get; set; default = false; }
		
		/**
		 * The progress for this dock item.
		 */
		public double Progress { get; set; default = 0; }
		
		/**
		 * Show the item's progress or not.
		 */
		public bool ProgressVisible { get; set; default = false; }
		
		int position = -1;
		/**
		 * The dock item's position on the dock.
		 */
		public int Position {
			get {
				return position;
			}
			set {
				if (position == value)
					return;
				
				if (LastPosition != position)
					LastPosition = position;
				
				position = value;
				
				// Only trigger animation if this isn't the initial position set
				if (LastPosition > -1) {
					LastMove = new DateTime.now_utc ();
					State |= ItemState.MOVE;
				}
			}
		}
		
		/**
		 * The dock item's last position on the dock.
		 */
		public int LastPosition { get; protected set; default = -1; }
		
		/**
		 * The item's current state.
		 */
		public ItemState State { get; protected set; default = ItemState.NORMAL; }
		
		/**
		 * The indicator shown for the item.
		 */
		public IndicatorState Indicator { get; protected set; default = IndicatorState.NONE; }
		
		/**
		 * The average color of this item's icon.
		 */
		public Drawing.Color AverageIconColor { get; protected set; default = Drawing.Color () { R = 0.0, G = 0.0, B = 0.0, A = 0.0 }; }
		
		/**
		 * The filename of the preferences backing file.
		 */
		public string DockItemFilename {
			owned get { return Prefs.get_filename (); }
		}
		
		/**
		 * The launcher associated with this item.
		 */
		public string Launcher {
			get { return Prefs.Launcher; }
		}
		
		/**
		 * The underlying preferences for this item.
		 */
		public DockItemPreferences Prefs { get; construct; }
		
		DockSurface? surface = null;
		DockSurface? background_surface = null;
		DockSurface? foreground_surface = null;
		
		/**
		 * Creates a new dock item.
		 */
		public DockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		construct
		{
			Prefs.deleted.connect (handle_deleted);
			Gtk.IconTheme.get_default ().changed.connect (icon_theme_changed);
			notify["Icon"].connect (reset_icon_buffer);
			notify["ForcePixbuf"].connect (reset_icon_buffer);
			
			notify["Count"].connect (reset_foreground_buffer);
			notify["CountVisible"].connect (reset_foreground_buffer);
			notify["Progress"].connect (reset_foreground_buffer);
			notify["ProgressVisible"].connect (reset_foreground_buffer);
		}
		
		~DockItem ()
		{
			Prefs.deleted.disconnect (handle_deleted);
			Gtk.IconTheme.get_default ().changed.disconnect (icon_theme_changed);
			notify["Icon"].disconnect (reset_icon_buffer);
			notify["ForcePixbuf"].disconnect (reset_icon_buffer);
			
			notify["Count"].disconnect (reset_foreground_buffer);
			notify["CountVisible"].disconnect (reset_foreground_buffer);
			notify["Progress"].disconnect (reset_foreground_buffer);
			notify["ProgressVisible"].disconnect (reset_foreground_buffer);
		}
		
		/**
		 * Signal handler called when the underlying preferences file is deleted.
		 */
		protected void handle_deleted ()
		{
			deleted ();
		}
		
		/**
		 * Deletes the underlying preferences file.
		 */
		public void delete ()
		{
			Prefs.delete ();
		}
		
		/**
		 * Resets the buffer for this item's icon and requests a redraw.
		 */
		protected void reset_icon_buffer ()
		{
			surface = null;
			background_surface = null;
			foreground_surface = null;
			
			needs_redraw ();
		}
		
		/**
		 * Resets the buffers for this item's icon.
		 */
		public void reset_buffers ()
		{
			background_surface = null;
			foreground_surface = null;
		}
		
		public void unset_move_state ()
		{
			State &= ~ItemState.MOVE;
		}
		
		void reset_foreground_buffer ()
		{
			foreground_surface = null;
		}
		
		void icon_theme_changed ()
		{
			// Put Gtk.IconTheme.changed emmitted signals in idle queue to avoid
			// race conditions with concurrent handles
			Gdk.threads_add_idle (() => {
				reset_icon_buffer ();
				return false;
			});
		}
		
		unowned DockSurface get_surface (int width, int height, DockSurface model)
		{
			if (surface == null || width != surface.Width || height != surface.Height) {
				surface = new DockSurface.with_dock_surface (width, height, model);
				
				Logger.verbose ("DockItem.draw_icon (width = %i, height = %i)", width, height);
				draw_icon (surface);
				
				AverageIconColor = surface.average_color ();
			}
			
			return surface;
		}
		
		/**
		 * Returns the background surface for this item.
		 *
		 * The draw_func may pass through the given previously computed surface
		 * or change it as needed. This surface will be buffered internally.
		 *
		 * Passing null as draw_func will destroy the internal background buffer.
		 *
		 * @param draw_func function which creates/changes the background surface
		 * @return the background surface of this item which may not be changed
		 */
		public unowned DockSurface? get_background_surface (DrawItemFunc? draw_func = null)
			requires (surface != null)
		{
			if (draw_func != null)
				background_surface = draw_func (this, surface, background_surface);
			else
				background_surface = null;
			
			return background_surface;
		}
		
		/**
		 * Returns the foreground surface for this item.
		 *
		 * The draw_func may pass through the given previously computed surface
		 * or change it as needed. This surface will be buffered internally.
		 *
		 * Passing null as draw_func will destroy the internal foreground buffer.
		 *
		 * @param draw_func function which creates/changes the foreground surface
		 * @return the background surface of this item which may not be changed
		 */
		public unowned DockSurface? get_foreground_surface (DrawItemFunc? draw_func = null)
			requires (surface != null)
		{
			if (draw_func != null)
				foreground_surface = draw_func (this, surface, foreground_surface);
			else
				foreground_surface = null;
			
			return foreground_surface;
		}
		
		/**
		 * Returns a copy of the dock surface for this item.
		 *
		 * It will trigger an internal redraw if the requested size
		 * isn't matching the cache.
		 *
		 * @param width width of the icon surface
		 * @param height height of the icon surface
		 * @param model existing surface to use as basis of new surface
		 * @return the copied dock surface for this item
		 */
		public DockSurface get_surface_copy (int width, int height, DockSurface model)
		{
			return get_surface (width, height, model).copy ();
		}

		/**
		 * Draws the item's icon onto a surface.
		 *
		 * @param surface the surface to draw on
		 */
		protected virtual void draw_icon (DockSurface surface)
		{
			Pixbuf? pbuf = ForcePixbuf;
			if (pbuf == null)
				pbuf = DrawingService.load_icon (Icon, surface.Width, surface.Height);
			else
				pbuf = DrawingService.ar_scale (pbuf, surface.Width, surface.Height);
			
			unowned Cairo.Context cr = surface.Context;
			cairo_set_source_pixbuf (cr, pbuf, (surface.Width - pbuf.width) / 2, (surface.Height - pbuf.height) / 2);
			cr.paint ();
		}
		
		/**
		 * Check the validity of this item.
		 *
		 * @return Whether or not this item is valid for the .dockitem given
		 */
		public virtual bool is_valid ()
		{
			return File.new_for_uri (Prefs.Launcher).query_exists ();
		}
		
		/**
		 * Copy all property value of this dockitem instance to target instance.
		 *
		 * @param target the dockitem to copy the values to
		 */
		public void copy_values_to (DockItem target)
		{
			foreach (var prop in get_class ().list_properties ()) {
				// Skip non-copyable properties to avoid warnings
				if ((prop.flags & ParamFlags.WRITABLE) == 0
					|| (prop.flags & ParamFlags.CONSTRUCT_ONLY) != 0)
					continue;
				
				var name = prop.get_name ();
				
				// Do not copy these
				if (name == "Provider")
				    continue;
				
				var type = prop.value_type;
				var val = Value (type);
				get_property (name, ref val);
				target.set_property (name, val);
			}
		}
	}
}
