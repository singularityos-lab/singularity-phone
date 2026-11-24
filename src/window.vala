using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Phone {

    public class PhoneWindow : Singularity.Widgets.Window {
        private const int ACTION_HEIGHT = 56;
        private PhoneApp app;
        private Voice voice;
        private Stack main_stack;
        private Stack page_stack;
        private BubbleSwitcher switcher;
        private string page = "keypad";
        private Label number_label;
        private Button erase;
        private Button call_button;
        private ListBox recents;
        private Stack recents_stack;
        private Label call_number;
        private Label call_status;
        private Widget call_actions;
        private Widget answer_actions;
        private Button tones_button;
        private Button mute_button;
        private Revealer tones_revealer;
        private Label tones_label;
        private Call? current = null;
        private uint tick_id = 0;
        private Singularity.Widgets.Toast? last_toast = null;
        private ToastOverlay keypad_toasts;
        private ToastOverlay call_toasts;
        private ulong[] handlers = {};
        private ulong log_handler = 0;

        public PhoneWindow (PhoneApp app) {
            Object (application: app);
            this.app = app;
            voice = Voice.get_default ();
            set_title (_("Phone"));
            set_default_size (400, 780);

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

            switcher = new BubbleSwitcher ();
            switcher.add_option ("keypad", _("Keypad"));
            switcher.add_option ("recents", _("Recents"));
            switcher.add_option ("missed", _("Missed"));
            switcher.selected.connect ((id) => show_page (id));
            add_bubble_widget (switcher);
            main_stack.notify["visible-child-name"].connect (() => {
                switcher.visible = main_stack.visible_child_name == "main";
            });
            page_stack.add_css_class ("phone-pages");

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

        public void show_page (string id) {
            if (switcher.active_option != id) {
                switcher.set_active (id);
                return;
            }
            page = id;
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
            var box = new Box (Orientation.VERTICAL, 0);

            number_label = new Label ("");
            number_label.add_css_class ("phone-display");
            number_label.vexpand = true;
            number_label.ellipsize = Pango.EllipsizeMode.START;
            number_label.selectable = true;
            number_label.focusable = false;
            keypad_toasts = new ToastOverlay ();
            keypad_toasts.vexpand = true;
            keypad_toasts.child = number_label;
            box.append (keypad_toasts);

            var keys = new Box (Orientation.VERTICAL, 8);
            var pad = new Keypad ();
            pad.pressed.connect ((k) => {
                if (k == "+" && number_label.label.has_suffix ("0")) set_number (number_label.label.substring (0, number_label.label.length - 1) + "+");
                else set_number (number_label.label + k);
            });
            keys.append (pad);

            var actions = new Grid ();
            actions.column_homogeneous = true;
            actions.column_spacing = 8;
            actions.attach (new Box (Orientation.HORIZONTAL, 0), 0, 0);
            call_button = action_button ("call-start-symbolic", _("Call"), "suggested-action");
            call_button.clicked.connect (() => dial (number_label.label));
            actions.attach (call_button, 1, 0);
            erase = new Button.from_icon_name ("edit-clear-symbolic");
            erase.add_css_class ("osk-key");
            erase.add_css_class ("osk-key-special");
            erase.focus_on_click = false;
            erase.tooltip_text = _("Delete");
            erase.update_property (AccessibleProperty.LABEL, _("Delete"), -1);
            erase.clicked.connect (() => backspace ());
            var hold = new GestureLongPress ();
            hold.pressed.connect (() => {
                hold.set_state (EventSequenceState.CLAIMED);
                set_number ("");
            });
            erase.add_controller (hold);
            actions.attach (erase, 2, 0);
            keys.append (actions);

            box.append (key_panel (keys));
            set_number ("");
            return box;
        }

        private Widget key_panel (Widget keys) {
            var panel = new Box (Orientation.VERTICAL, 0);
            panel.add_css_class ("osk");
            var clamp = new Clamp (keys, 420);
            clamp.hexpand = true;
            panel.append (clamp);
            return panel;
        }

        private void set_number (string text) {
            number_label.label = text;
            if (text.char_count () > 13) number_label.add_css_class ("long");
            else number_label.remove_css_class ("long");
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
                    show_tones (true);
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
            recents.add_css_class ("boxed-list");
            recents.valign = Align.START;
            recents.margin_top = recents.margin_bottom = 12;
            recents.margin_start = recents.margin_end = 12;
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
            scroll.child = new Clamp (recents);
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
            name.add_css_class ("title-3");
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
            var box = new Box (Orientation.VERTICAL, 0);

            var head = new Box (Orientation.VERTICAL, 12);
            head.vexpand = true;
            head.valign = Align.CENTER;
            call_status = new Label ("");
            call_status.add_css_class ("title-4");
            call_status.add_css_class ("phone-call-status");
            head.append (call_status);
            call_number = new Label ("");
            call_number.add_css_class ("phone-display");
            call_number.ellipsize = Pango.EllipsizeMode.START;
            head.append (call_number);
            call_toasts = new ToastOverlay ();
            call_toasts.vexpand = true;
            call_toasts.child = head;
            box.append (call_toasts);

            var actions = new Box (Orientation.VERTICAL, 12);
            var row = new Box (Orientation.HORIZONTAL, 12);
            row.homogeneous = true;
            tones_button = action_button ("dev.sinty.phone-keypad-symbolic", _("Keypad"));
            tones_button.clicked.connect (() => show_tones (!tones_revealer.reveal_child));
            row.append (tones_button);
            mute_button = action_button ("microphone-sensitivity-muted-symbolic", _("Mute"));
            mute_button.clicked.connect (() => toggle_mute ());
            row.append (mute_button);
            actions.append (row);
            var end = action_button ("call-stop-symbolic", _("End Call"), "destructive-action");
            end.clicked.connect (() => hang_up ());
            actions.append (end);
            call_actions = action_area (actions);
            box.append (call_actions);

            var answers = new Box (Orientation.HORIZONTAL, 12);
            answers.homogeneous = true;
            var decline = action_button ("call-stop-symbolic", _("Decline"), "destructive-action");
            decline.clicked.connect (() => hang_up ());
            answers.append (decline);
            var accept = action_button ("call-start-symbolic", _("Accept"), "suggested-action");
            accept.clicked.connect (() => accept_call ());
            answers.append (accept);
            answer_actions = action_area (answers);
            box.append (answer_actions);

            var tones = new Box (Orientation.VERTICAL, 8);
            tones_label = new Label ("");
            tones_label.add_css_class ("title-1");
            tones_label.ellipsize = Pango.EllipsizeMode.START;
            tones.append (tones_label);
            var pad = new Keypad ();
            pad.pressed.connect ((k) => send_tone (k));
            tones.append (pad);
            tones_revealer = new Revealer ();
            tones_revealer.transition_type = RevealerTransitionType.SLIDE_UP;
            tones_revealer.child = key_panel (tones);
            box.append (tones_revealer);
            return box;
        }

        private Widget action_area (Widget actions) {
            var clamp = new Clamp (actions, 420);
            clamp.margin_top = 12;
            clamp.margin_bottom = 24;
            clamp.margin_start = clamp.margin_end = 16;
            return clamp;
        }

        private Button action_button (string icon, string label, string? style = null) {
            var content = new Box (Orientation.HORIZONTAL, 8);
            content.halign = Align.CENTER;
            content.append (new Image.from_icon_name (icon));
            content.append (new Label (label));
            var b = new Button ();
            b.child = content;
            b.set_size_request (-1, ACTION_HEIGHT);
            b.add_css_class ("pill");
            if (style != null) b.add_css_class (style);
            b.update_property (AccessibleProperty.LABEL, label, -1);
            return b;
        }

        private void show_tones (bool shown) {
            tones_revealer.reveal_child = shown;
            if (shown) tones_button.add_css_class ("suggested-action");
            else tones_button.remove_css_class ("suggested-action");
        }

        private void toggle_mute () {
            if (current == null) return;
            var call = current;
            voice.set_mute.begin (call, !call.muted, (o, res) => {
                try {
                    voice.set_mute.end (res);
                } catch (Error e) {
                    show_error (e);
                }
            });
        }

        private void update_start () {
            if (current != null) return;
            main_stack.visible_child_name = voice.available ? "main" : "welcome";
            switcher.visible = voice.available;
        }

        private void update_missed () {
            int n = app.unseen_missed ();
            switcher.set_option_label ("missed", n > 0 ? _("Missed (%d)").printf (n) : _("Missed"));
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
            bool active = call.state == CallState.ACTIVE;
            if (!active) show_tones (false);
            tones_button.sensitive = active;
            mute_button.sensitive = active;
            mute_button.visible = call.can_mute;
            if (call.muted) mute_button.add_css_class ("suggested-action");
            else mute_button.remove_css_class ("suggested-action");
            update_status ();
            if (tick_id == 0) tick_id = Timeout.add_seconds (1, () => {
                update_status ();
                return Source.CONTINUE;
            });
            main_stack.visible_child_name = "call";
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
            show_tones (false);
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
                    show_error (e);
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
                    show_error (e);
                }
            });
        }

        private void accept_call () {
            if (current == null) return;
            voice.accept.begin (current, (o, res) => {
                try {
                    voice.accept.end (res);
                } catch (Error e) {
                    show_error (e);
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
                    show_error (e);
                }
            });
        }

        public void show_toast (string text) {
            present_toast (new Singularity.Widgets.Toast (text));
        }

        private void show_error (Error e) {
            present_toast (Singularity.ModemError.toast (e));
        }

        private void present_toast (Singularity.Widgets.Toast toast) {
            if (last_toast != null) last_toast.dismiss ();
            last_toast = toast;
            if (main_stack.visible_child_name == "call") call_toasts.add_toast (toast);
            else if (main_stack.visible_child_name == "main" && page == "keypad") keypad_toasts.add_toast (toast);
            else add_toast (toast);
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

        public void prepare_move () throws Singularity.Migration.MigrationError {
            if (current != null) throw new Singularity.Migration.MigrationError.UNSUPPORTED (_("Calls stay on this device until they end"));
        }

        public Variant save_migration () {
            var d = new VariantDict ();
            d.insert_value ("page", new Variant.string (page));
            d.insert_value ("number", new Variant.string (number_label.label));
            return d.end ();
        }

        public void restore_migration (Variant data) {
            var d = new VariantDict (data);
            string wanted = (d.lookup_value ("page", VariantType.STRING) ?? new Variant.string ("keypad")).get_string ();
            if (wanted in new string[] { "keypad", "recents", "missed" }) show_page (wanted);
            set_number ((d.lookup_value ("number", VariantType.STRING) ?? new Variant.string ("")).get_string ());
        }

        public void prefill (string number) {
            if (current != null) return;
            show_page ("keypad");
            set_number (number);
        }
    }
}
