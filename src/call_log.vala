namespace Singularity.Apps.Phone {

    public class LogEntry : Object {
        public string number { get; set; default = ""; }
        public bool incoming { get; set; default = false; }
        public bool answered { get; set; default = false; }
        public int64 started { get; set; default = 0; }
        public int64 duration { get; set; default = 0; }

        public bool missed {
            get { return incoming && !answered; }
        }
    }

    public class CallLog : Object {
        private const int LIMIT = 500;

        public Gee.ArrayList<LogEntry> entries = new Gee.ArrayList<LogEntry> ();
        private string path;

        public signal void changed ();

        public CallLog () {
            path = Path.build_filename (Environment.get_user_data_dir (), "singularity-phone", "calls.json");
            load ();
        }

        private void load () {
            var parser = new Json.Parser ();
            try {
                parser.load_from_file (path);
            } catch (Error e) {
                return;
            }
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return;
            foreach (var node in root.get_array ().get_elements ()) {
                if (node.get_node_type () != Json.NodeType.OBJECT) continue;
                var o = node.get_object ();
                var e = new LogEntry ();
                e.number = o.get_string_member_with_default ("number", "");
                e.incoming = o.get_boolean_member_with_default ("incoming", false);
                e.answered = o.get_boolean_member_with_default ("answered", false);
                e.started = o.get_int_member_with_default ("started", 0);
                e.duration = o.get_int_member_with_default ("duration", 0);
                if (e.number != "") entries.add (e);
            }
        }

        private void save () {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var e in entries) {
                b.begin_object ();
                b.set_member_name ("number").add_string_value (e.number);
                b.set_member_name ("incoming").add_boolean_value (e.incoming);
                b.set_member_name ("answered").add_boolean_value (e.answered);
                b.set_member_name ("started").add_int_value (e.started);
                b.set_member_name ("duration").add_int_value (e.duration);
                b.end_object ();
            }
            b.end_array ();
            var gen = new Json.Generator ();
            gen.root = b.get_root ();
            try {
                DirUtils.create_with_parents (Path.get_dirname (path), 0700);
                FileUtils.set_contents (path, gen.to_data (null));
            } catch (Error e) {
                warning ("phone: %s", e.message);
            }
        }

        public void record (Call call) {
            var e = new LogEntry ();
            e.number = call.number;
            e.incoming = call.incoming;
            e.answered = call.answered != 0;
            e.started = call.started;
            e.duration = call.answered != 0 ? get_real_time () / 1000000 - call.answered : 0;
            entries.insert (0, e);
            while (entries.size > LIMIT) entries.remove_at (entries.size - 1);
            save ();
            changed ();
        }

        public void forget (LogEntry e) {
            entries.remove (e);
            save ();
            changed ();
        }

        public void clear () {
            entries.clear ();
            save ();
            changed ();
        }

        public int missed_since (int64 stamp) {
            int n = 0;
            foreach (var e in entries) {
                if (e.started <= stamp) break;
                if (e.missed) n++;
            }
            return n;
        }
    }

    public static string format_duration (int64 seconds) {
        int h = (int) (seconds / 3600), m = (int) ((seconds / 60) % 60), sec = (int) (seconds % 60);
        if (h > 0) return "%d:%02d:%02d".printf (h, m, sec);
        return "%d:%02d".printf (m, sec);
    }

    public static string format_when (int64 stamp) {
        var dt = new DateTime.from_unix_local (stamp);
        var now = new DateTime.now_local ();
        if (dt.get_year () == now.get_year () && dt.get_day_of_year () == now.get_day_of_year ()) return dt.format ("%H:%M");
        if (now.difference (dt) < 6 * TimeSpan.DAY) return dt.format ("%A");
        return dt.format ("%x");
    }
}
