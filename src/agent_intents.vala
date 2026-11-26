namespace Singularity.Apps.Phone {

    internal class PhoneIntents : Object {

        private static string state_id (CallState s) {
            switch (s) {
                case CallState.DIALING: return "dialing";
                case CallState.RINGING_OUT: return "ringing_out";
                case CallState.RINGING_IN: return "ringing_in";
                case CallState.ACTIVE: return "active";
                case CallState.HELD: return "held";
                case CallState.WAITING: return "waiting";
                case CallState.TERMINATED: return "ended";
                default: return "unknown";
            }
        }

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key).strip () : "";
        }

        private static void call_json (Json.Builder b, Call c) {
            b.begin_object ();
            b.set_member_name ("id").add_string_value (c.path);
            b.set_member_name ("number").add_string_value (c.number);
            b.set_member_name ("state").add_string_value (state_id (c.state));
            b.set_member_name ("incoming").add_boolean_value (c.incoming);
            if (c.answered != 0) b.set_member_name ("seconds").add_int_value (get_real_time () / 1000000 - c.answered);
            b.set_member_name ("muted").add_boolean_value (c.muted);
            b.end_object ();
        }

        private static Call live (string id) throws Error {
            var voice = Voice.get_default ();
            if (id != "") {
                var c = voice.calls[id];
                if (c == null || !c.state.is_live ()) throw new IOError.NOT_FOUND ("no call %s is in progress; see phone_calls", id);
                return c;
            }
            Call? only = null;
            foreach (var c in voice.calls.values) {
                if (!c.state.is_live ()) continue;
                if (only != null) throw new IOError.INVALID_ARGUMENT ("more than one call is in progress: give the id from phone_calls");
                only = c;
            }
            if (only == null) throw new IOError.NOT_FOUND ("no call is in progress");
            return only;
        }

        private static string number_of (Json.Object args) throws Error {
            var n = text (args, "number");
            var ok = n.length > 0;
            for (int i = 0; i < n.length; i++) {
                var ch = n[i];
                if (!(ch.isdigit () || ch == '+' || ch == '*' || ch == '#' || ch == ' ' || ch == '-' || ch == '(' || ch == ')')) ok = false;
            }
            if (!ok) throw new IOError.INVALID_ARGUMENT ("give a phone number: digits, +, *, #");
            return n;
        }

        private static async void dial (PhoneApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold ();
            try {
                var n = number_of (args);
                var c = yield Voice.get_default ().dial (n);
                var b = new Json.Builder ();
                call_json (b, c);
                reply (b.get_root (), null);
            } catch (Error e) {
                reply (null, e);
            } finally {
                app.release ();
            }
        }

        private static async void on_call (PhoneApp app, Json.Object args, string what, owned Singularity.AppIntentReply reply) {
            app.hold ();
            try {
                var voice = Voice.get_default ();
                var c = live (text (args, "id"));
                if (what == "answer") {
                    if (c.state != CallState.RINGING_IN && c.state != CallState.WAITING) throw new IOError.INVALID_ARGUMENT ("this call is not ringing");
                    yield voice.accept (c);
                } else if (what == "hang_up") {
                    yield voice.hang_up (c);
                } else if (what == "mute") {
                    if (!c.can_mute) throw new IOError.NOT_SUPPORTED ("this call cannot be muted");
                    yield voice.set_mute (c, !args.has_member ("on") || args.get_boolean_member ("on"));
                } else if (what == "keys") {
                    var keys = text (args, "keys");
                    if (keys == "") throw new IOError.INVALID_ARGUMENT ("give the keys to press");
                    for (int i = 0; i < keys.length; i++) {
                        var ch = keys[i];
                        if (!(ch.isdigit () || ch == '*' || ch == '#')) throw new IOError.INVALID_ARGUMENT ("keys are digits, * and #");
                    }
                    for (int i = 0; i < keys.length; i++) yield voice.send_tone (c, keys.substring (i, 1));
                }
                var b = new Json.Builder ();
                call_json (b, c);
                reply (b.get_root (), null);
            } catch (Error e) {
                reply (null, e);
            } finally {
                app.release ();
            }
        }

        internal static void install (PhoneApp app) {
            var agent = app.agent;
            agent.add_intent ("phone_status", "Whether this device can make voice calls, and the calls in progress.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var voice = Voice.get_default ();
                    var b = new Json.Builder ();
                    b.begin_object ();
                    b.set_member_name ("can_call").add_boolean_value (voice.available);
                    b.set_member_name ("calls").begin_array ();
                    foreach (var c in voice.calls.values) if (c.state.is_live ()) call_json (b, c);
                    b.end_array ();
                    b.set_member_name ("missed_unseen").add_int_value (app.log.missed_since (app.missed_seen_at ()));
                    b.end_object ();
                    return b.get_root ();
                });
            agent.add_intent ("phone_history", "Recent calls, newest first: number, incoming or outgoing, answered or missed, when and how long.",
                "{\"type\":\"object\",\"properties\":{\"missed\":{\"type\":\"boolean\"},\"number\":{\"type\":\"string\"},\"limit\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var missed = args.has_member ("missed") && args.get_boolean_member ("missed");
                    var filter = text (args, "number").replace (" ", "");
                    var limit = args.has_member ("limit") ? (int) args.get_int_member ("limit") : 50;
                    var b = new Json.Builder ();
                    b.begin_array ();
                    int n = 0;
                    foreach (var e in app.log.entries) {
                        if (n >= limit) break;
                        if (missed && !e.missed) continue;
                        if (filter != "" && !e.number.replace (" ", "").contains (filter)) continue;
                        b.begin_object ();
                        b.set_member_name ("number").add_string_value (e.number);
                        b.set_member_name ("direction").add_string_value (e.incoming ? "incoming" : "outgoing");
                        b.set_member_name ("answered").add_boolean_value (e.answered);
                        b.set_member_name ("missed").add_boolean_value (e.missed);
                        b.set_member_name ("when").add_string_value (new DateTime.from_unix_local (e.started).format ("%Y-%m-%d %H:%M"));
                        b.set_member_name ("seconds").add_int_value (e.duration);
                        b.end_object ();
                        n++;
                    }
                    b.end_array ();
                    return b.get_root ();
                });
            agent.add_async_intent ("phone_dial", "Call a number now. It rings the other person, so ask first unless the user asked for this call.",
                "{\"type\":\"object\",\"properties\":{\"number\":{\"type\":\"string\"}},\"required\":[\"number\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args, reply) => {
                    dial.begin (app, args, (owned) reply);
                });
            agent.add_intent ("phone_prepare", "Open the keypad with a number typed in, for the user to place the call.",
                "{\"type\":\"object\",\"properties\":{\"number\":{\"type\":\"string\"}},\"required\":[\"number\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var n = number_of (args);
                    app.window ().present ();
                    app.window ().prefill (n);
                    return new Json.Node.alloc ().init_string ("the keypad shows %s".printf (n));
                });
            agent.add_async_intent ("phone_answer", "Answer the ringing call (id from phone_status when there is more than one).",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args, reply) => {
                    on_call.begin (app, args, "answer", (owned) reply);
                });
            agent.add_async_intent ("phone_hang_up", "End a call, or decline it while it rings.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args, reply) => {
                    on_call.begin (app, args, "hang_up", (owned) reply);
                });
            agent.add_async_intent ("phone_mute", "Mute or unmute the microphone in a call.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"on\":{\"type\":\"boolean\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    on_call.begin (app, args, "mute", (owned) reply);
                });
            agent.add_async_intent ("phone_keys", "Press keypad keys during a call, for menus that ask for a choice or a code.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"keys\":{\"type\":\"string\"}},\"required\":[\"keys\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args, reply) => {
                    on_call.begin (app, args, "keys", (owned) reply);
                });
        }
    }
}
