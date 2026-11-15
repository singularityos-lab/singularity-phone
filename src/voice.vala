namespace Singularity.Apps.Phone {

    public enum CallState {
        UNKNOWN,
        DIALING,
        RINGING_OUT,
        RINGING_IN,
        ACTIVE,
        HELD,
        WAITING,
        TERMINATED;

        public bool is_live () {
            return this != UNKNOWN && this != TERMINATED;
        }
    }

    public class Call : Object {
        public string path { get; construct; }
        public string number { get; set; default = ""; }
        public bool incoming { get; set; default = false; }
        public CallState state { get; set; default = CallState.UNKNOWN; }
        public int64 started { get; set; default = 0; }
        public int64 answered { get; set; default = 0; }

        public Call (string path) {
            Object (path: path);
        }
    }

    public class Voice : Object {
        public const string NAME = "org.freedesktop.ModemManager1";
        public const string ROOT = "/org/freedesktop/ModemManager1";
        public const string VOICE = "org.freedesktop.ModemManager1.Modem.Voice";
        public const string CALL = "org.freedesktop.ModemManager1.Call";

        private static Voice? instance = null;
        private DBusConnection? bus = null;
        private bool started = false;

        public string modem { get; private set; default = ""; }
        public Gee.HashMap<string, Call> calls = new Gee.HashMap<string, Call> ();

        public signal void modems_changed ();
        public signal void call_added (Call call);
        public signal void call_changed (Call call);

        public static Voice get_default () {
            if (instance == null) instance = new Voice ();
            return instance;
        }

        public bool available {
            get { return modem != ""; }
        }

        public async void start () {
            if (started) return;
            started = true;
            try {
                bus = yield Bus.get (BusType.SYSTEM);
            } catch (Error e) {
                return;
            }
            bus.signal_subscribe (NAME, "org.freedesktop.DBus.ObjectManager", null, ROOT, null, DBusSignalFlags.NONE,
                () => refresh.begin ());
            bus.signal_subscribe (NAME, VOICE, "CallAdded", null, null, DBusSignalFlags.NONE, (c, s, p, i, m, args) => {
                track.begin (args.get_child_value (0).get_string ());
            });
            bus.signal_subscribe (NAME, CALL, "StateChanged", null, null, DBusSignalFlags.NONE, (c, s, path, i, m, args) => {
                var call = calls[path];
                if (call == null) return;
                apply_state (call, (CallState) args.get_child_value (1).get_int32 ());
            });
            yield refresh ();
        }

        public async void refresh () {
            if (bus == null) return;
            string found = "";
            try {
                var reply = yield bus.call (NAME, ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", null,
                    new VariantType ("(a{oa{sa{sv}}})"), DBusCallFlags.NONE, -1);
                var iter = reply.get_child_value (0).iterator ();
                string path;
                Variant ifaces;
                while (iter.next ("{o@a{sa{sv}}}", out path, out ifaces)) {
                    if (ifaces.lookup_value (VOICE, null) != null && (found == "" || strcmp (path, found) < 0)) found = path;
                }
            } catch (Error e) {
            }
            if (found == modem) return;
            modem = found;
            modems_changed ();
        }

        private void apply_state (Call call, CallState state) {
            if (call.state == state) return;
            if (state == CallState.ACTIVE && call.answered == 0) call.answered = get_real_time () / 1000000;
            call.state = state;
            call_changed (call);
            if (state == CallState.TERMINATED) calls.unset (call.path);
        }

        private async Call? track (string path, bool created = false) {
            if (calls.has_key (path)) return calls[path];
            var call = new Call (path);
            call.started = get_real_time () / 1000000;
            try {
                var reply = yield bus.call (NAME, path, "org.freedesktop.DBus.Properties", "GetAll", new Variant ("(s)", CALL),
                    new VariantType ("(a{sv})"), DBusCallFlags.NONE, -1);
                var props = reply.get_child_value (0);
                var number = props.lookup_value ("Number", VariantType.STRING);
                var direction = props.lookup_value ("Direction", VariantType.INT32);
                var state = props.lookup_value ("State", VariantType.INT32);
                if (number != null) call.number = number.get_string ();
                call.incoming = direction != null && direction.get_int32 () == 1;
                if (state != null) call.state = (CallState) state.get_int32 ();
            } catch (Error e) {
                return null;
            }
            if (calls.has_key (path)) return calls[path];
            if (!call.state.is_live () && !(created && call.state == CallState.UNKNOWN)) return null;
            calls[path] = call;
            call_added (call);
            return call;
        }

        private async void invoke (string path, string iface, string method, Variant? args, string reply = "()") throws Error {
            if (bus == null) throw new IOError.NOT_CONNECTED (_("No modem"));
            yield bus.call (NAME, path, iface, method, args, new VariantType (reply), DBusCallFlags.NONE, 60000);
        }

        public async Call dial (string number) throws Error {
            if (!available) throw new IOError.NOT_FOUND (_("There is no modem with voice calls on this device"));
            var props = new VariantBuilder (new VariantType ("a{sv}"));
            props.add ("{sv}", "number", new Variant.string (number));
            var reply = yield bus.call (NAME, modem, VOICE, "CreateCall", new Variant ("(a{sv})", props),
                new VariantType ("(o)"), DBusCallFlags.NONE, 60000);
            var call = yield track (reply.get_child_value (0).get_string (), true);
            if (call == null) throw new IOError.FAILED (_("The call could not be started"));
            yield invoke (call.path, CALL, "Start", null);
            return call;
        }

        public async void accept (Call call) throws Error {
            yield invoke (call.path, CALL, "Accept", null);
        }

        public async void hang_up (Call call) throws Error {
            yield invoke (call.path, CALL, "Hangup", null);
        }

        public async void send_tone (Call call, string tone) throws Error {
            yield invoke (call.path, CALL, "SendDtmf", new Variant ("(s)", tone));
        }
    }
}
