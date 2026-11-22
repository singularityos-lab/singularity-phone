using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Phone {

    public class PhoneWindow : Singularity.Widgets.Window {
        private PhoneApp app;
        private Voice voice;
        private Stack main_stack;
        private Stack page_stack;
        private Box sidebar_box;
        private Gee.HashMap<string, SidebarRow> nav_rows = new Gee.HashMap<string, SidebarRow> ();
        private Label missed_count;
        private string page = "keypad";
        private Label number_label;
        private Button erase;
        private Button call_button;
        private ListBox recents;
        private Stack recents_stack;
        private Label call_number;
        private Label call_status;
        private Box call_actions;
        private Box answer_actions;
        private Revealer tones_revealer;
        private Label tones_label;
        private Call? current = null;
        private uint tick_id = 0;
        private Singularity.Widgets.Toast? last_toast = null;
        private ulong[] handlers = {};
        private ulong log_handler = 0;

        public PhoneWindow (PhoneApp app) {
            Object (application: app);
            this.app = app;
            voice = Voice.get_default ();
            set_title (_("Phone"));
            set_default_size (760, 640);

            var sidebar = new AppSidebar (200);
            sidebar_box = new Box (Orientation.VERTICAL, 2);
            sidebar_box.valign = Align.START;
            sidebar.box.append (sidebar_box);
            sidebar_box.append (nav_row ("keypad", "dev.sinty.phone-keypad-symbolic", _("Keypad")));
            sidebar_box.append (nav_row ("recents", "document-open-recent-symbolic", _("Recents")));
            var missed = nav_row ("missed", "call-missed-symbolic", _("Missed"));
            missed_count = new Label ("");
            missed_count.add_css_class ("phone-nav-count");
            missed_count.visible = false;
            var inner = missed.get_child () as Box;
            if (inner != null) inner.append (missed_count);
            sidebar_box.append (missed);
            set_sidebar (sidebar);

            page_stack = new Stack ();
            page_stack.transition_type = StackTransitionType.CROSSFADE;
            page_stack.add_named (build_keypad (), "keypad");
            page_stack.add_named (build_recents (), "recents");

            main_stack = new Stack ();
            main_stack.transition_type = StackTransitionType.CROSSFADE;
            main_stack.add_named (build_welcome (), "welcome");
            main_stack.add_named (page_stack, "main");
            main_stack.add_named (build_call (), "call");
            set_content (main_stack);

            var keys = new EventControllerKey ();
            keys.key_pressed.connect (on_key);
            ((Widget) this).add_controller (keys);

            handlers += voice.modems_changed.connect (update_start);
            handlers += voice.call_added.connect (on_call);
            handlers += voice.call_changed.connect (on_call);
            log_handler = app.log.changed.connect (() => {
                rebuild_recents ();
                update_missed ();
            });
            rebuild_recents ();
            update_missed ();
            update_start ();
        }

        private SidebarRow nav_row (string id, string icon, string label) {
            var row = new SidebarRow (icon, label);
            row.clicked.connect (() => show_page (id));
            nav_rows[id] = row;
            row.set_active (id == page);
            return row;
        }

        public void show_page (string id) {
            page = id;
            foreach (var e in nav_rows.entries) e.value.set_active (e.key == id);
            page_stack.visible_child_name = id == "keypad" ? "keypad" : "recents";
            if (id != "keypad") {
                rebuild_recents ();
                if (id == "missed") app.seen_missed ();
            }
            update_missed ();
        }

        private Widget build_welcome () {
            var welcome = new WelcomePage ();
            welcome.app_icon_name = "dev.sinty.phone";
            welcome.title = _("Phone");
            welcome.subtitle = _("This device has no modem that can make voice calls. Calls appear here as soon as one is connected.");
            return welcome;
        }

        private Widget build_keypad () {
            var box = new Box (Orientation.VERTICAL, 18);
            box.valign = Align.CENTER;
            box.halign = Align.CENTER;
            box.margin_top = box.margin_bottom = 24;
            box.margin_start = box.margin_end = 24;

            var head = new Box (Orientation.HORIZONTAL, 6);
            number_label = new Label ("");
            number_label.add_css_class ("phone-display");
            number_label.hexpand = true;
            number_label.ellipsize = Pango.EllipsizeMode.START;
            number_label.selectable = true;
            number_label.width_chars = 12;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.set_size_request (36, -1);
            erase = new Button.from_icon_name ("edit-clear-symbolic");
            erase.add_css_class ("flat");
            erase.tooltip_text = _("Delete");
            erase.valign = Align.CENTER;
            erase.clicked.connect (() => backspace ());
            var hold = new GestureLongPress ();
            hold.pressed.connect (() => set_number (""));
            erase.add_controller (hold);
            head.append (spacer);
            head.append (number_label);
            head.append (erase);
            box.append (head);

            var pad = new Keypad ();
            pad.pressed.connect ((k) => {
                if (k == "+" && number_label.label.has_suffix ("0")) set_number (number_label.label.substring (0, number_label.label.length - 1) + "+");
                else set_number (number_label.label + k);
            });
            box.append (pad);

            call_button = new Button.from_icon_name ("call-start-symbolic");
            call_button.add_css_class ("phone-call");
            call_button.add_css_class ("suggested-action");
            call_button.halign = Align.CENTER;
            call_button.tooltip_text = _("Call");
            call_button.update_property (AccessibleProperty.LABEL, _("Call"), -1);
            call_button.clicked.connect (() => dial (number_label.label));
            box.append (call_button);
            set_number ("");
            return box;
        }

        private void set_number (string text) {
            number_label.label = text;
            erase.opacity = text == "" ? 0 : 1;
            erase.sensitive = text != "";
        }

        private void backspace () {
            var t = number_label.label;
            if (t.length > 0) set_number (t.substring (0, t.length - 1));
        }

        private bool on_key (uint keyval, uint code, Gdk.ModifierType state) {
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && main_stack.visible_child_name == "main") {
                if (keyval == Gdk.Key.@1) show_page ("keypad");
                else if (keyval == Gdk.Key.@2) show_page ("recents");
                else if (keyval == Gdk.Key.@3) show_page ("missed");
                else return false;
                return true;
            }
            if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) != 0) return false;
            unichar c = Gdk.keyval_to_unicode (keyval);
            bool dial_key = c.isdigit () || c == '*' || c == '#' || c == '+';
            if (main_stack.visible_child_name == "call") {
                if (dial_key && current != null && current.state == CallState.ACTIVE) {
                    send_tone (c.to_string ());
                    return true;
                }
                if (keyval == Gdk.Key.Escape && current != null) {
                    hang_up ();
                    return true;
                }
                return false;
            }
            if (main_stack.visible_child_name != "main") return false;
            if (dial_key) {
                show_page ("keypad");
                set_number (number_label.label + c.to_string ());
                return true;
            }
            if (page != "keypad") return false;
            if (keyval == Gdk.Key.BackSpace) {
                backspace ();
                return true;
            }
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                dial (number_label.label);
                return true;
            }
            return false;
        }

        private Widget build_recents () {
            recents = new ListBox ();
            recents.add_css_class ("phone-recents");
            recents.margin_top = recents.margin_bottom = 6;
            recents.selection_mode = SelectionMode.NONE;
            recents.activate_on_single_click = true;
            recents.update_property (AccessibleProperty.LABEL, _("Recent Calls"), -1);
            recents.row_activated.connect ((row) => {
                var e = row.get_data<LogEntry> ("entry");
                if (e != null) dial (e.number);
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = recents;
            var empty = new StatusPage ();
            empty.icon_name = "document-open-recent-symbolic";
            empty.title = _("No Calls");
            empty.description = _("Calls you make and receive are listed here");
            recents_stack = new Stack ();
            recents_stack.add_named (scroll, "list");
            recents_stack.add_named (empty, "empty");
            return recents_stack;
        }

        private void rebuild_recents () {
            Widget? child;
            while ((child = recents.get_first_child ()) != null) recents.remove (child);
            bool only_missed = page == "missed";
            int n = 0;
            foreach (var e in app.log.entries) {
                if (only_missed && !e.missed) continue;
                recents.append (recent_row (e));
                n++;
            }
            var empty = recents_stack.get_child_by_name ("empty") as StatusPage;
            if (empty != null) {
                empty.title = only_missed ? _("No Missed Calls") : _("No Calls");
                empty.icon_name = only_missed ? "call-missed-symbolic" : "document-open-recent-symbolic";
            }
            recents_stack.visible_child_name = n > 0 ? "list" : "empty";
        }

        private ListBoxRow recent_row (LogEntry e) {
            var row = new ListBoxRow ();
            row.set_data<LogEntry> ("entry", e);
            var box = new Box (Orientation.HORIZONTAL, 12);
            box.add_css_class ("phone-recent");
            var icon = new Image.from_icon_name (e.missed ? "call-missed-symbolic" : (e.incoming ? "call-incoming-symbolic" : "call-outgoing-symbolic"));
            if (e.missed) icon.add_css_class ("error");
            else icon.add_css_class ("dim-label");
            box.append (icon);
            var text = new Box (Orientation.VERTICAL, 2);
            text.hexpand = true;
            var name = new Label (e.number);
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            if (e.missed) name.add_css_class ("error");
            text.append (name);
            string kind = e.missed ? _("Missed") : (e.incoming ? _("Incoming") : _("Outgoing"));
            if (e.duration > 0) kind = "%s, %s".printf (kind, format_duration (e.duration));
            else if (!e.incoming && !e.answered) kind = _("Not answered");
            var sub = new Label (kind);
            sub.xalign = 0;
            sub.add_css_class ("dim-label");
            sub.add_css_class ("caption");
            text.append (sub);
            box.append (text);
            var when = new Label (format_when (e.started));
            when.add_css_class ("dim-label");
            when.add_css_class ("caption");
            box.append (when);
            row.child = box;
            row.update_property (AccessibleProperty.LABEL, "%s, %s, %s".printf (e.number, kind, format_when (e.started)), -1);
            var click = new GestureClick ();
            click.button = Gdk.BUTTON_SECONDARY;
            click.pressed.connect ((n, x, y) => recent_menu (row, e, x, y));
            row.add_controller (click);
            return row;
        }

        private void recent_menu (Widget row, LogEntry e, double x, double y) {
            var pop = new Popover ();
            pop.has_arrow = false;
            pop.set_parent (row);
            pop.pointing_to = { (int) x, (int) y, 1, 1 };
            var box = new Box (Orientation.VERTICAL, 0);
            box.append (menu_item (pop, _("Call"), () => dial (e.number)));
            box.append (menu_item (pop, _("Send Message"), () => app.message (e.number)));
            box.append (menu_item (pop, _("Copy Number"), () => get_clipboard ().set_text (e.number)));
            box.append (menu_item (pop, _("Remove from Recents"), () => app.log.forget (e)));
            pop.child = box;
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        private delegate void MenuAction ();

        private Button menu_item (Popover pop, string label, owned MenuAction action) {
            var b = new Button.with_label (label);
            b.add_css_class ("flat");
            var l = b.child as Label;
            if (l != null) l.xalign = 0;
            b.clicked.connect (() => {
                pop.popdown ();
                action ();
            });
            return b;
        }

        private Widget build_call () {
            var box = new Box (Orientation.VERTICAL, 12);
            box.add_css_class ("phone-call-page");
            box.valign = Align.CENTER;
            box.halign = Align.CENTER;
            box.margin_start = box.margin_end = 24;

            var avatar = new Image.from_icon_name ("avatar-default-symbolic");
            avatar.pixel_size = 64;
            avatar.add_css_class ("phone-call-avatar");
            box.append (avatar);
            call_number = new Label ("");
            call_number.add_css_class ("phone-call-number");
            call_number.ellipsize = Pango.EllipsizeMode.START;
            box.append (call_number);
            call_status = new Label ("");
            call_status.add_css_class ("dim-label");
            call_status.add_css_class ("phone-call-status");
            box.append (call_status);

            tones_label = new Label ("");
            tones_label.add_css_class ("phone-tones");
            var tones = new Box (Orientation.VERTICAL, 12);
            tones.margin_top = 12;
            tones.append (tones_label);
            var pad = new Keypad ();
            pad.pressed.connect ((k) => send_tone (k));
            tones.append (pad);
            tones_revealer = new Revealer ();
            tones_revealer.transition_type = RevealerTransitionType.SLIDE_DOWN;
            tones_revealer.child = tones;
            box.append (tones_revealer);

            call_actions = new Box (Orientation.HORIZONTAL, 24);
            call_actions.halign = Align.CENTER;
            call_actions.margin_top = 24;
            var keypad = round_button ("dev.sinty.phone-keypad-symbolic", _("Keypad"), null);
            keypad.clicked.connect (() => tones_revealer.reveal_child = !tones_revealer.reveal_child);
            call_actions.append (round_wrap (keypad, _("Keypad")));
            var end = round_button ("call-stop-symbolic", _("End Call"), "destructive-action");
            end.clicked.connect (() => hang_up ());
            call_actions.append (round_wrap (end, _("End Call")));
            box.append (call_actions);

            answer_actions = new Box (Orientation.HORIZONTAL, 48);
            answer_actions.halign = Align.CENTER;
            answer_actions.margin_top = 24;
            var decline = round_button ("call-stop-symbolic", _("Decline"), "destructive-action");
            decline.clicked.connect (() => hang_up ());
            answer_actions.append (round_wrap (decline, _("Decline")));
            var accept = round_button ("call-start-symbolic", _("Accept"), "suggested-action");
            accept.clicked.connect (() => accept_call ());
            answer_actions.append (round_wrap (accept, _("Accept")));
            box.append (answer_actions);
            return box;
        }

        private Widget round_wrap (Button b, string label) {
            var box = new Box (Orientation.VERTICAL, 6);
            box.append (b);
            var l = new Label (label);
            l.add_css_class ("caption");
            l.add_css_class ("dim-label");
            box.append (l);
            return box;
        }

        private Button round_button (string icon, string label, string? style) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("phone-call");
            if (style != null) b.add_css_class (style);
            b.tooltip_text = label;
            b.update_property (AccessibleProperty.LABEL, label, -1);
            return b;
        }

        private void update_start () {
            if (current != null) return;
            main_stack.visible_child_name = voice.available ? "main" : "welcome";
            set_sidebar_visible (voice.available);
        }

        private void update_missed () {
            int n = app.unseen_missed ();
            missed_count.label = n.to_string ();
            missed_count.visible = n > 0;
        }

        private void on_call (Call call) {
            if (current != null && current != call && current.state.is_live ()) return;
            if (!call.state.is_live ()) {
                if (call == current) finish ();
                return;
            }
            current = call;
            call_number.label = call.number != "" ? call.number : _("Unknown Number");
            bool ringing = call.state == CallState.RINGING_IN || call.state == CallState.WAITING;
            answer_actions.visible = ringing;
            call_actions.visible = !ringing;
            if (call.state != CallState.ACTIVE) tones_revealer.reveal_child = false;
            update_status ();
            if (tick_id == 0) tick_id = Timeout.add_seconds (1, () => {
                update_status ();
                return Source.CONTINUE;
            });
            main_stack.visible_child_name = "call";
            set_sidebar_visible (false);
            if (ringing) present ();
        }

        private void update_status () {
            if (current == null) return;
            switch (current.state) {
                case CallState.DIALING:
                    call_status.label = _("Calling…");
                    break;
                case CallState.RINGING_OUT:
                    call_status.label = _("Ringing…");
                    break;
                case CallState.RINGING_IN:
                case CallState.WAITING:
                    call_status.label = _("Incoming Call");
                    break;
                case CallState.HELD:
                    call_status.label = _("On Hold");
                    break;
                case CallState.ACTIVE:
                    call_status.label = format_duration (get_real_time () / 1000000 - current.answered);
                    break;
                default:
                    call_status.label = "";
                    break;
            }
        }

        private void finish () {
            current = null;
            tones_label.label = "";
            tones_revealer.reveal_child = false;
            if (tick_id != 0) {
                Source.remove (tick_id);
                tick_id = 0;
            }
            foreach (var c in voice.calls.values) {
                if (c.state.is_live ()) {
                    on_call (c);
                    return;
                }
            }
            set_number ("");
            update_start ();
        }

        public void dial (string number) {
            var n = number.strip ();
            if (n == "") {
                if (app.log.entries.size > 0 && page == "keypad") set_number (app.log.entries[0].number);
                return;
            }
            set_number (n);
            voice.dial.begin (n, (o, res) => {
                try {
                    voice.dial.end (res);
                } catch (Error e) {
                    show_toast (Singularity.ModemError.describe (e));
                }
            });
        }

        private void hang_up () {
            if (current == null) return;
            var call = current;
            voice.hang_up.begin (call, (o, res) => {
                try {
                    voice.hang_up.end (res);
                } catch (Error e) {
                    show_toast (Singularity.ModemError.describe (e));
                }
            });
        }

        private void accept_call () {
            if (current == null) return;
            voice.accept.begin (current, (o, res) => {
                try {
                    voice.accept.end (res);
                } catch (Error e) {
                    show_toast (Singularity.ModemError.describe (e));
                }
            });
        }

        private void send_tone (string key) {
            if (current == null || current.state != CallState.ACTIVE) return;
            tones_label.label += key;
            voice.send_tone.begin (current, key, (o, res) => {
                try {
                    voice.send_tone.end (res);
                } catch (Error e) {
                    show_toast (Singularity.ModemError.describe (e));
                }
            });
        }

        public void show_toast (string text) {
            if (last_toast != null) last_toast.dismiss ();
            last_toast = new Singularity.Widgets.Toast (text);
            add_toast (last_toast);
        }

        public override bool close_request () {
            foreach (var id in handlers) voice.disconnect (id);
            handlers = {};
            if (log_handler != 0) app.log.disconnect (log_handler);
            log_handler = 0;
            if (tick_id != 0) Source.remove (tick_id);
            tick_id = 0;
            return base.close_request ();
        }

        public void prefill (string number) {
            if (current != null) return;
            show_page ("keypad");
            set_number (number);
        }
    }
}
