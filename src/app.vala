using Gtk;

namespace Singularity.Apps.Phone {

    [DBus (name = "dev.sinty.Phone1")]
    public class PhoneBus : Object {
        private unowned PhoneApp app;

        public PhoneBus (PhoneApp app) {
            this.app = app;
        }

        public void dial (string number) throws Error {
            app.window ().present ();
            app.window ().dial (number);
        }

        public void prefill (string number) throws Error {
            app.window ().present ();
            app.window ().prefill (number);
        }
    }

    public class PhoneApp : Singularity.Application {
        public CallLog log;
        private PhoneWindow? win = null;
        private uint bus_id = 0;
        private int64 missed_seen = 0;
        private HubBridge? hub = null;

        public PhoneApp () {
            Object (application_id: "dev.sinty.phone", flags: ApplicationFlags.HANDLES_OPEN);
        }

        public override bool dbus_register (DBusConnection connection, string object_path) throws Error {
            if (!base.dbus_register (connection, object_path)) return false;
            bus_id = connection.register_object ("/dev/sinty/phone/Phone", new PhoneBus (this));
            return true;
        }

        public override void dbus_unregister (DBusConnection connection, string object_path) {
            if (bus_id != 0) connection.unregister_object (bus_id);
            bus_id = 0;
            base.dbus_unregister (connection, object_path);
        }

        protected override void startup () {
            base.startup ();
            log = new CallLog ();
            missed_seen = load_seen ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => quit ());
            add_action (quit_action);
            set_accels_for_action ("app.quit", { "<Control>q" });
            var voice = Voice.get_default ();
            voice.call_added.connect ((call) => {
                if (call.state == CallState.RINGING_IN && (win == null || !win.is_active)) notify_incoming (call);
            });
            voice.call_changed.connect ((call) => {
                if (!call.state.is_live ()) withdraw_notification ("incoming");
                if (call.state != CallState.TERMINATED) return;
                log.record (call);
                if (call.incoming && call.answered == 0 && (win == null || !win.is_active)) notify_missed (call);
            });
            voice.start.begin ();
            hub = new HubBridge (this);
        }

        protected override void activate () {
            window ().present ();
        }

        protected override void open (File[] files, string hint) {
            var w = window ();
            w.present ();
            foreach (var f in files) {
                string number = number_of (f.get_uri ());
                if (number != "") w.prefill (number);
            }
        }

        public static string number_of (string uri) {
            if (!uri.down ().has_prefix ("tel:")) return "";
            string rest = uri.substring (4);
            int cut = rest.index_of_char (';');
            if (cut >= 0) rest = rest.substring (0, cut);
            string number = Uri.unescape_string (rest) ?? rest;
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (number.get_next_char (ref i, out c)) {
                if (c.isdigit () || c == '+' || c == '*' || c == '#') sb.append_unichar (c);
            }
            return sb.str;
        }

        public PhoneWindow window () {
            if (win == null) {
                win = new PhoneWindow (this);
                win.close_request.connect (() => {
                    win = null;
                    return false;
                });
            }
            return win;
        }

        private void notify_incoming (Call call) {
            var n = new GLib.Notification (_("Incoming Call"));
            n.set_body (call.number != "" ? call.number : _("Unknown Number"));
            n.set_priority (NotificationPriority.URGENT);
            n.set_default_action ("app.activate");
            send_notification ("incoming", n);
        }

        private void notify_missed (Call call) {
            var n = new GLib.Notification (_("Missed Call"));
            n.set_body (call.number != "" ? call.number : _("Unknown Number"));
            n.set_default_action ("app.activate");
            send_notification ("missed-" + call.started.to_string (), n);
        }

        private string seen_path () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity-phone", "missed-seen");
        }

        private int64 load_seen () {
            try {
                string s;
                FileUtils.get_contents (seen_path (), out s);
                return int64.parse (s.strip ());
            } catch (Error e) {
                return 0;
            }
        }

        public int unseen_missed () {
            return log.missed_since (missed_seen);
        }

        public void seen_missed () {
            missed_seen = get_real_time () / 1000000;
            try {
                DirUtils.create_with_parents (Path.get_dirname (seen_path ()), 0700);
                FileUtils.set_contents (seen_path (), missed_seen.to_string ());
            } catch (Error e) {
                warning ("phone: %s", e.message);
            }
        }

        public void message (string number) {
            Bus.get.begin (BusType.SESSION, null, (o, res) => {
                try {
                    var bus = Bus.get.end (res);
                    bus.call.begin ("dev.sinty.messages", "/dev/sinty/messages/Messages", "dev.sinty.Messages1", "Compose",
                        new Variant ("(sss)", "", number, ""), null, DBusCallFlags.NONE, -1, null, (b, r) => {
                            try {
                                bus.call.end (r);
                            } catch (Error e) {
                                if (win != null) win.show_toast (_("Messages could not be opened"));
                            }
                        });
                } catch (Error e) {
                }
            });
        }

        private const string CSS = """
.singularity-app:not(.ssd-mode) .phone-pages > * { padding-top: 44px; }
.phone-display { font-size: 48px; font-weight: 300; padding: 12px 20px; font-feature-settings: "tnum"; }
.phone-display.long { font-size: 34px; }
.phone-keypad button.phone-key { min-height: 68px; padding: 0; }
.phone-key-digit { font-size: 30px; }
.phone-key-letters { font-size: 12px; letter-spacing: 0.12em; opacity: 0.6; min-height: 14px; }
.phone-call-status { font-feature-settings: "tnum"; }
.phone-recent { padding: 10px 14px; }
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-phone", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-phone", "UTF-8");
        Intl.textdomain ("singularity-phone");
        return new PhoneApp ().run (args);
    }
}
