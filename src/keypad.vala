using Gtk;

namespace Singularity.Apps.Phone {

    public class Keypad : Box {
        private const string[] KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" };
        private const string[] LETTERS = { "", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ", "", "+", "" };

        public signal void pressed (string key);

        public Keypad () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("phone-keypad");
            var grid = new Grid ();
            grid.hexpand = true;
            grid.row_spacing = 8;
            grid.column_spacing = 8;
            grid.row_homogeneous = true;
            grid.column_homogeneous = true;
            for (int i = 0; i < KEYS.length; i++) {
                grid.attach (key_button (KEYS[i], LETTERS[i]), i % 3, i / 3);
            }
            append (grid);
        }

        private Button key_button (string key, string letters) {
            var b = new Button ();
            b.add_css_class ("osk-key");
            b.add_css_class ("phone-key");
            b.focus_on_click = false;
            var box = new Box (Orientation.VERTICAL, 0);
            box.valign = Align.CENTER;
            var digit = new Label (key);
            digit.add_css_class ("phone-key-digit");
            box.append (digit);
            var sub = new Label (letters);
            sub.add_css_class ("phone-key-letters");
            box.append (sub);
            b.child = box;
            b.update_property (AccessibleProperty.LABEL, key, -1);
            b.clicked.connect (() => pressed (key));
            if (key == "0") {
                var hold = new GestureLongPress ();
                hold.pressed.connect (() => {
                    hold.set_state (EventSequenceState.CLAIMED);
                    pressed ("+");
                });
                b.add_controller (hold);
            }
            return b;
        }
    }
}
