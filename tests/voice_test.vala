using Singularity.Apps.Phone;
using Singularity.Telephony;

void test_log () {
    var log = new CallLog ();
    log.clear ();
    var a = new Call ("/a");
    a.number = "+391234";
    a.incoming = true;
    a.started = 100;
    log.record (a);
    var b = new Call ("/b");
    b.number = "555";
    b.started = 200;
    b.answered = get_real_time () / 1000000 - 65;
    log.record (b);
    assert (log.entries.size == 2);
    assert (log.entries[0].number == "555");
    assert (log.entries[0].duration >= 65);
    assert (log.entries[1].missed);
    assert (log.missed_since (0) == 1);
    assert (log.missed_since (150) == 0);
    var again = new CallLog ();
    assert (again.entries.size == 2);
    assert (again.entries[1].number == "+391234");
    again.forget (again.entries[1]);
    assert (new CallLog ().entries.size == 1);
}

void test_format () {
    assert (format_duration (5) == "0:05");
    assert (format_duration (65) == "1:05");
    assert (format_duration (3725) == "1:02:05");
    assert (CallState.ACTIVE.is_live ());
    assert (!CallState.TERMINATED.is_live ());
}

int main (string[] args) {
    Environment.set_variable ("XDG_DATA_HOME", Path.build_filename (Environment.get_variable ("PHONE_TEST_DIR") ?? ".", "test-data"), true);
    Test.init (ref args);
    Test.add_func ("/phone/log", test_log);
    Test.add_func ("/phone/format", test_format);
    return Test.run ();
}
