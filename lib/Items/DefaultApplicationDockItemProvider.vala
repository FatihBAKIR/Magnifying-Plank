//
//  Copyright (C) 2013 Rico Tzschichholz
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

using Gee;

using Plank.Factories;
using Plank.Widgets;

using Plank.Services;
using Plank.Services.Windows;

namespace Plank.Items
{
	/**
	 * The default container and controller class for managing application dock items on a dock.
	 */
	public class DefaultApplicationDockItemProvider : ApplicationDockItemProvider
	{
		public DockPreferences Prefs { get; construct; }
		
		/**
		 * Creates the default container for dock items.
		 *
		 * @param prefs the preferences of the dock which owns this provider
		 */
		public DefaultApplicationDockItemProvider (DockPreferences prefs, File launchers_dir)
		{
			// If we made the default-launcher-directory,
			// assume a first run and pre-populate with launchers
			if (Paths.ensure_directory_exists (launchers_dir)) {
				debug ("Adding default dock items...");
				Factory.item_factory.make_default_items ();
				debug ("done.");
			}
			
			Object (Prefs : prefs, LaunchersDir : launchers_dir, HandlesTransients : true);
		}
		
		construct
		{
			serialize_item_positions ();
			
			Prefs.notify["CurrentWorkspaceOnly"].connect (handle_setting_changed);
			
			var wnck_screen = Wnck.Screen.get_default ();
			wnck_screen.active_window_changed.connect (handle_window_changed);
			wnck_screen.active_workspace_changed.connect (handle_workspace_changed);
			wnck_screen.viewports_changed.connect (handle_viewports_changed);
			
			item_positions_changed.connect (serialize_item_positions);
			items_changed.connect (serialize_item_positions);
		}
		
		~DefaultApplicationDockItemProvider ()
		{
			Prefs.notify["CurrentWorkspaceOnly"].disconnect (handle_setting_changed);
			
			var wnck_screen = Wnck.Screen.get_default ();
			wnck_screen.active_window_changed.disconnect (handle_window_changed);
			wnck_screen.active_workspace_changed.disconnect (handle_workspace_changed);
			wnck_screen.viewports_changed.disconnect (handle_viewports_changed);
			
			item_positions_changed.disconnect (serialize_item_positions);
			items_changed.disconnect (serialize_item_positions);
		}
		
		protected override void update_visible_items ()
		{
			Logger.verbose ("DefaultDockItemProvider.update_visible_items ()");
			
			if (Prefs.CurrentWorkspaceOnly) {
				var active_workspace = Wnck.Screen.get_default ().get_active_workspace ();
				foreach (var item in internal_items) {
					unowned TransientDockItem? transient = (item as TransientDockItem);
					item.IsVisible = (transient == null || transient.App == null
						|| WindowControl.has_window_on_workspace (transient.App, active_workspace));
				}
			} else {
				foreach (var item in internal_items)
					item.IsVisible = true;
			}
			
			base.update_visible_items ();
		}
		
		/**
		 * Serializes the item positions to the preferences.
		 */
		void serialize_item_positions ()
		{
			var item_list = "";
			foreach (var item in internal_items) {
				if (!(item is TransientDockItem) && item.DockItemFilename.length > 0) {
					if (item_list.length > 0)
						item_list += ";;";
					item_list += item.DockItemFilename;
				}
			}
			
			if (Prefs.DockItems != item_list)
				Prefs.DockItems = item_list;
		}
		
		protected override ArrayList<DockItem> load_items ()
		{
			var result = new ArrayList<DockItem> ();
			
			var items = base.load_items ();
			
			var existing_items = new ArrayList<DockItem> ();
			var new_items = new ArrayList<DockItem> ();
			var favs = new ArrayList<string> ();
			
			foreach (var item in items) {
				if (Prefs.DockItems.contains (item.DockItemFilename))
					existing_items.add (item);
				else
					new_items.add (item);
			
				if ((item is ApplicationDockItem) && !(item is TransientDockItem))
					favs.add (item.Launcher);
			}
			
			// add saved dockitems based on their serialized order
			var dockitems = Prefs.DockItems.split (";;");
			foreach (var dockitem in dockitems)
				foreach (var item in existing_items)
					if (dockitem == item.DockItemFilename) {
						result.add (item);
						break;
					}
			
			// add new dockitems
			foreach (var item in new_items)
				result.add (item);
			
			Matcher.get_default ().set_favorites (favs);
			
			return result;
		}
		
		protected override void add_running_apps ()
		{
			foreach (var app in Matcher.get_default ().active_launchers ()) {
				var found = item_for_application (app);
				if (found != null) {
					found.App = app;
					continue;
				}
				
				if (!app.is_user_visible () || WindowControl.get_num_windows (app) <= 0)
					continue;
				
				var new_item = new TransientDockItem.with_application (app);
				
				add_item_without_signaling (new_item);
			}
		}
		
		protected override void app_opened (Bamf.Application app)
		{
			var found = item_for_application (app);
			if (found != null) {
				found.App = app;
				return;
			}
			
			if (!app.is_user_visible () || WindowControl.get_num_windows (app) <= 0)
				return;
			
			var new_item = new TransientDockItem.with_application (app);
			
			add_item (new_item);
		}
		
		void app_closed (DockItem remove)
		{
			if (remove is TransientDockItem
				&& !(((TransientDockItem) remove).has_unity_info ()))
				remove_item (remove);
		}
		
		void handle_window_changed (Wnck.Window? previous)
		{
			if (!Prefs.CurrentWorkspaceOnly)
				return;
			
			if (previous == null
				|| previous.get_workspace () == previous.get_screen ().get_active_workspace ())
				return;
			
			update_visible_items ();
		}
		
		void handle_workspace_changed (Wnck.Screen screen, Wnck.Workspace previously_active_space)
		{
			if (!Prefs.CurrentWorkspaceOnly
				|| screen.get_active_workspace ().is_virtual ())
				return;
			
			update_visible_items ();
		}
		
		void handle_viewports_changed (Wnck.Screen screen)
		{
			if (!Prefs.CurrentWorkspaceOnly
				|| !screen.get_active_workspace ().is_virtual ())
				return;
			
			update_visible_items ();
		}
		
		protected override void item_signals_connect (DockItem item)
		{
			base.item_signals_connect (item);
			
			unowned ApplicationDockItem? appitem = (item as ApplicationDockItem);
			if (appitem != null) {
				appitem.app_closed.connect (app_closed);
				appitem.pin_launcher.connect (pin_item);
			}
		}
		
		protected override void item_signals_disconnect (DockItem item)
		{
			base.item_signals_disconnect (item);
			
			unowned ApplicationDockItem? appitem = (item as ApplicationDockItem);
			if (appitem != null) {
				appitem.app_closed.disconnect (app_closed);
				appitem.pin_launcher.disconnect (pin_item);
			}
		}
		
		public void pin_item (DockItem item)
		{
			if (!internal_items.contains (item)) {
				critical ("Item '%s' does not exist in this DockItemProvider.", item.Text);
				return;
			}
			
			Logger.verbose ("DefaultDockItemProvider.pin_item ('%s[%s]')", item.Text, item.DockItemFilename);

			unowned ApplicationDockItem? app_item = (item as ApplicationDockItem);
			if (app_item == null)
				return;
			
			// delay automatic add of new dockitems while creating this new one
			delay_items_monitor ();
			
			if (item is TransientDockItem) {
				var dockitem_file = Factory.item_factory.make_dock_item (item.Launcher, LaunchersDir);
				if (dockitem_file == null)
					return;
				
				var new_item = new ApplicationDockItem.with_dockitem_file (dockitem_file);
				item.copy_values_to (new_item);
				
				replace_item (new_item, item);
				serialize_item_positions ();
			} else {
				item.delete ();
			}
			
			resume_items_monitor ();
		}
	}
}
