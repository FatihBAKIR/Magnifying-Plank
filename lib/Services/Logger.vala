//
//  Copyright (C) 2011 Robert Dyer
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

namespace Plank.Services
{
	/**
	 * Controls what messages show in the console log.
	 */
	public enum LogLevel
	{
		/**
		 * Extra debugging info. A *LOT* of messages.
		 */
		VERBOSE,
		/**
		 * Debugging messages that help track what the application is doing.
		 */
		DEBUG,
		/**
		 * General information messages. Similar to debug but perhaps useful to non-debug users.
		 */
		INFO,
		/**
		 * Messages that also show a libnotify message.
		 */
		NOTIFY,
		/**
		 * Any messsage that is a warning.
		 */
		WARN,
		/**
		 * Any message considered an error.  These can be recovered from but might make the application function abnormally.
		 */
		ERROR,
		/**
		 * Any message considered fatal.  These generally break the application.
		 */
		FATAL,
	}
	
	enum ConsoleColor
	{
		BLACK,
		RED,
		GREEN,
		YELLOW,
		BLUE,
		MAGENTA,
		CYAN,
		WHITE,
	}
	
	/**
	 * A logging class to display all console messages in a nice colored format.
	 */
	public class Logger : GLib.Object
	{
		class LogMessage : GLib.Object
		{
			public LogLevel Level { get; construct; }
			public string Message { get; construct; }
			
			public LogMessage (LogLevel level, string message)
			{
				GLib.Object (Level : level, Message : message);
			}
		}
		
		/**
		 * The current log level.  Controls what log messages actually appear on the console.
		 */
		public static LogLevel DisplayLevel { get; set; default = LogLevel.NOTIFY; }
		
		static string AppName { get; set; }
		
		static Object? queue_lock = null;
		
		static ArrayList<LogMessage> log_queue;
		static bool is_writing;
		
		static Regex? re = null;
		
		Logger ()
		{
		}
		
		/**
		 * Initializes the logger for the application.
		 *
		 * @param app_name the name of the application
		 */
		public static void initialize (string app_name)
		{
			AppName = app_name;
			is_writing = false;
			log_queue = new ArrayList<LogMessage> ();
			try {
				re = new Regex ("""[(]?.*?([^/]*?)(\.2)?\.vala(:\d+)[)]?:\s*(.*)""");
			} catch { }
			
			Log.set_default_handler (glib_log_func);
		}
		
		static string format_message (string msg)
		{
			if (re != null && re.match (msg)) {
				var parts = re.split (msg);
				return "[%s%s] %s".printf (parts[1], parts[3], parts[4]);
			}
			return msg;
		}
		
		/**
		 * Displays a log message using libnotify.  Also displays on the console.
		 *
		 * @param msg the log message to display
		 * @param icon the icon to display in the notification
		 */
		public static void notification (string msg, string icon = "")
		{
			// TODO display the message using libnotify
			write (LogLevel.NOTIFY, format_message (msg));
		}
		
		/**
		 * Displays a verbose log message to the console.
		 *
		 * @param msg the log message to display
		 */
		public static void verbose (string msg, ...)
		{
			// NOTE using a local var is needed for valac 0.12/0.14 to avoid invalid c-code
			var vargs = va_list ();
			write (LogLevel.VERBOSE, format_message (msg.vprintf (vargs)));
		}
		
		static string get_time ()
		{
			var now = new DateTime.now_local ();
			return "%.2d:%.2d:%.2d.%.6d".printf (now.get_hour (), now.get_minute (), now.get_second (), now.get_microsecond ());
		}
		
		static void write (LogLevel level, string msg)
		{
			if (level < DisplayLevel)
				return;
			
			if (is_writing) {
				lock (queue_lock)
					log_queue.add (new LogMessage (level, msg));
			} else {
				is_writing = true;
				
				if (log_queue.size > 0) {
					var logs = log_queue;
					lock (queue_lock)
						log_queue = new ArrayList<LogMessage> ();
					
					foreach (var log in logs)
						print_log (log);
				}
				
				print_log (new LogMessage (level, msg));
				
				is_writing = false;
			}
		}
		
		static void print_log (LogMessage log)
		{
			set_color_for_level (log.Level);
			stdout.printf ("[%s %s]", log.Level.to_string ().substring (25), get_time ());
			
			reset_color ();
			stdout.printf (" %s\n", log.Message);
		}
		
		static void set_color_for_level (LogLevel level)
		{
			switch (level) {
			case LogLevel.VERBOSE:
				set_foreground (ConsoleColor.CYAN);
				break;
			case LogLevel.DEBUG:
				set_foreground (ConsoleColor.GREEN);
				break;
			case LogLevel.INFO:
				set_foreground (ConsoleColor.BLUE);
				break;
			case LogLevel.NOTIFY:
				set_foreground (ConsoleColor.MAGENTA);
				break;
			case LogLevel.WARN:
			default:
				set_foreground (ConsoleColor.YELLOW);
				break;
			case LogLevel.ERROR:
				set_foreground (ConsoleColor.RED);
				break;
			case LogLevel.FATAL:
				set_background (ConsoleColor.RED);
				set_foreground (ConsoleColor.WHITE);
				break;
			}
		}
		
		static void reset_color ()
		{
			stdout.printf ("\x001b[0m");
		}
		
		static void set_foreground (ConsoleColor color)
		{
			set_color (color, true);
		}
		
		static void set_background (ConsoleColor color)
		{
			set_color (color, false);
		}
		
		static void set_color (ConsoleColor color, bool isForeground)
		{
			var color_code = color + 30 + 60;
			if (!isForeground)
				color_code += 10;
			stdout.printf ("\x001b[%dm", color_code);
		}
		
		static void glib_log_func (string? d, LogLevelFlags flags, string msg)
		{
			var domain = "";
			if (d != null)
				domain = "[%s] ".printf (d ?? "");
			
			var message = msg.replace ("\n", "").replace ("\r", "");
			message = "%s%s".printf (domain, message);
			
			switch (flags) {
			case LogLevelFlags.LEVEL_CRITICAL:
				write (LogLevel.FATAL, format_message (message));
				write (LogLevel.FATAL, format_message (AppName + " will not function properly."));
				break;
			
			case LogLevelFlags.LEVEL_ERROR:
				write (LogLevel.ERROR, format_message (message));
				break;
			
			case LogLevelFlags.LEVEL_INFO:
			case LogLevelFlags.LEVEL_MESSAGE:
				write (LogLevel.INFO, format_message (message));
				break;
			
			case LogLevelFlags.LEVEL_DEBUG:
				write (LogLevel.DEBUG, format_message (message));
				break;
			
			case LogLevelFlags.LEVEL_WARNING:
			default:
				write (LogLevel.WARN, format_message (message));
				break;
			}
		}
	}
}
