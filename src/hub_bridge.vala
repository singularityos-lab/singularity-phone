namespace Singularity.Apps.Phone {

    public class HubBridge : Object {
        private const int LIMIT = 40;
        private const string ACCOUNT = "phone:calls";

        private unowned PhoneApp app;
        private Gee.HashSet<string> published = new Gee.HashSet<string> ();
        private Gee.HashSet<string> read = new Gee.HashSet<string> ();
        private Gee.HashSet<string> hidden = new Gee.HashSet<string> ();
        private string state_path;
        private uint flush_source = 0;

        public HubBridge (PhoneApp app) {
            this.app = app;
            state_path = Path.build_filename (Environment.get_user_data_dir (), "singularity-phone", "hub.json");
            load ();
            Singularity.Hub.install_action (app, on_action);
            app.log.changed.connect (queue_flush);
            Bus.watch_name (BusType.SESSION, Singularity.Hub.BUS_NAME, BusNameWatcherFlags.NONE, () => queue_flush (), null);
        }

        private static string id_of (LogEntry e) {
            return "%lld-%s".printf (e.started, e.number);
        }

        private void queue_flush () {
            if (flush_source != 0) return;
            flush_source = Timeout.add (300, () => {
                flush_source = 0;
                publish ();
                return Source.REMOVE;
            });
        }

        private void publish () {
            var account = new Singularity.Hub.Account (ACCOUNT, _("Calls"), Singularity.Hub.AccountKind.CALLS);
            account.icon_name = "call-start-symbolic";
            account.app_id = "dev.sinty.phone";
            Singularity.Hub.register_account (account);

            var keep = new Gee.HashSet<string> ();
            int n = 0;
            foreach (var e in app.log.entries) {
                if (n++ >= LIMIT) break;
                string id = id_of (e);
                if (hidden.contains (id)) continue;
                keep.add (id);
                var item = new Singularity.Hub.Item (ACCOUNT, id, e.missed ? Singularity.Hub.ItemKind.MISSED_CALL : Singularity.Hub.ItemKind.CALL);
                item.sender = e.number != "" ? e.number : _("Unknown Number");
                item.subject = e.missed ? _("Missed Call") : (e.incoming ? _("Incoming Call") : _("Outgoing Call"));
                item.preview = e.duration > 0 ? format_duration (e.duration) : "";
                item.timestamp = e.started;
                item.unread = e.missed && !read.contains (id);
                item.target = e.number;
                item.app_id = "dev.sinty.phone";
                Singularity.Hub.publish (item);
            }
            foreach (var id in published) {
                if (!keep.contains (id)) Singularity.Hub.withdraw (ACCOUNT, id);
            }
            published = keep;
            read.retain_all (keep);
            hidden.retain_all (all_ids ());
        }

        private Gee.HashSet<string> all_ids () {
            var set = new Gee.HashSet<string> ();
            foreach (var e in app.log.entries) set.add (id_of (e));
            return set;
        }

        private LogEntry? find (string id) {
            foreach (var e in app.log.entries) if (id_of (e) == id) return e;
            return null;
        }

        private void on_action (string account, string id, string action) {
            if (account != ACCOUNT) return;
            var e = find (id);
            switch (action) {
                case "mark-read":
                    read.add (id);
                    break;
                case "mark-unread":
                    read.remove (id);
                    break;
                case "delete":
                    hidden.add (id);
                    break;
                case "restore":
                    hidden.remove (id);
                    break;
                case "call":
                    if (e != null && e.number != "") {
                        read.add (id);
                        app.window ().present ();
                        app.window ().dial (e.number);
                    }
                    break;
                case "message":
                    if (e != null && e.number != "") app.message (e.number);
                    break;
                case "open":
                    app.activate ();
                    break;
                default:
                    return;
            }
            save ();
            queue_flush ();
        }

        private void load () {
            var parser = new Json.Parser ();
            try {
                parser.load_from_file (state_path);
            } catch (Error e) {
                return;
            }
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return;
            var o = root.get_object ();
            if (o.has_member ("read")) o.get_array_member ("read").foreach_element ((a, i, node) => read.add (node.get_string ()));
            if (o.has_member ("hidden")) o.get_array_member ("hidden").foreach_element ((a, i, node) => hidden.add (node.get_string ()));
        }

        private void save () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("read").begin_array ();
            foreach (var id in read) b.add_string_value (id);
            b.end_array ();
            b.set_member_name ("hidden").begin_array ();
            foreach (var id in hidden) b.add_string_value (id);
            b.end_array ();
            b.end_object ();
            var gen = new Json.Generator ();
            gen.root = b.get_root ();
            try {
                DirUtils.create_with_parents (Path.get_dirname (state_path), 0700);
                FileUtils.set_contents (state_path, gen.to_data (null));
            } catch (Error e) {
                warning ("phone: %s", e.message);
            }
        }
    }
}
