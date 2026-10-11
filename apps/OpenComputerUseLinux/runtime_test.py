import importlib.util
import pathlib
import sys
import types
import unittest
from unittest import mock


class FakeText:
    @staticmethod
    def get_character_count(_interface):
        return 5

    @staticmethod
    def get_text(_interface, _start, _end):
        return "hello"


class FakeEditableText:
    @staticmethod
    def insert_text(_interface, _offset, _text, _length):
        return True

    @staticmethod
    def set_text_contents(_interface, _text):
        return True


def load_runtime():
    gi = types.ModuleType("gi")
    gi.require_version = lambda *_args: None
    repository = types.ModuleType("gi.repository")
    repository.Atspi = types.SimpleNamespace(
        Text=FakeText,
        EditableText=FakeEditableText,
    )
    repository.Gdk = types.SimpleNamespace()
    gi.repository = repository

    runtime_path = pathlib.Path(__file__).with_name("runtime.py")
    spec = importlib.util.spec_from_file_location("open_computer_use_linux_runtime", runtime_path)
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(
        sys.modules,
        {"gi": gi, "gi.repository": repository},
    ):
        spec.loader.exec_module(module)
    return module


class InterfaceOnlyAccessible:
    def __init__(self, interfaces):
        self.interfaces = interfaces

    def get_interfaces(self):
        return self.interfaces

    def get_text_iface(self):
        return self

    def get_editable_text_iface(self):
        return self

    def get_child_count(self):
        return 0


class RuntimeInterfaceDetectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runtime = load_runtime()

    def test_text_value_uses_accessible_interfaces(self):
        node = InterfaceOnlyAccessible(["Accessible", "Text"])

        self.assertEqual(self.runtime.text_value(node), "hello")

    def test_insert_text_uses_accessible_interfaces(self):
        node = InterfaceOnlyAccessible(["Accessible", "Text", "EditableText"])

        self.assertTrue(self.runtime.insert_text(node, "hello"))

    def test_set_value_uses_accessible_interfaces(self):
        node = InterfaceOnlyAccessible(["Accessible", "Text", "EditableText"])

        self.assertTrue(self.runtime.set_element_value(node, "hello"))


class FakeKeySynthType:
    PRESS = "PRESS"
    RELEASE = "RELEASE"
    PRESSRELEASE = "PRESSRELEASE"
    SYM = "SYM"
    STRING = "STRING"
    LOCKMODIFIERS = "LOCKMODIFIERS"
    UNLOCKMODIFIERS = "UNLOCKMODIFIERS"


class FakeModifierType:
    SHIFT = 0
    CONTROL = 2
    ALT = 3
    META3 = 6


KEYSYMS = {"Return": 0xFF0D, "Tab": 0xFF09, "Down": 0xFF54}


class RuntimeKeyTests(unittest.TestCase):
    def setUp(self):
        self.runtime = load_runtime()
        self.events = []
        self.runtime.Atspi = types.SimpleNamespace(
            KeySynthType=FakeKeySynthType,
            ModifierType=FakeModifierType,
            generate_keyboard_event=lambda value, text, synth: self.events.append(
                (value, text, synth)
            ),
        )
        self.runtime.Gdk = types.SimpleNamespace(
            # Like GDK, unknown names map to VoidSymbol rather than 0.
            keyval_from_name=lambda name: KEYSYMS.get(name, 0xFFFFFF),
            unicode_to_keyval=lambda codepoint: codepoint,
        )

    def test_named_key_is_sent_as_keysym(self):
        self.runtime.send_key("Enter")

        self.assertEqual(self.events, [(0xFF0D, None, "SYM")])

    def test_modifiers_are_held_around_the_key(self):
        self.runtime.send_key("ctrl+shift+Tab")

        mask = (1 << FakeModifierType.CONTROL) | (1 << FakeModifierType.SHIFT)
        self.assertEqual(
            self.events,
            [
                (mask, None, "LOCKMODIFIERS"),
                (0xFF09, None, "SYM"),
                (mask, None, "UNLOCKMODIFIERS"),
            ],
        )

    def test_modified_character_is_sent_as_keysym(self):
        self.runtime.send_key("ctrl+a")

        mask = 1 << FakeModifierType.CONTROL
        self.assertEqual(self.events[1], (ord("a"), None, "SYM"))
        self.assertEqual(self.events[0], (mask, None, "LOCKMODIFIERS"))

    def test_modified_punctuation_is_sent_as_keysym(self):
        self.runtime.send_key("ctrl+/")

        self.assertEqual(self.events[1], (ord("/"), None, "SYM"))

    def test_unknown_key_name_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.runtime.send_key("NoSuchKey")

        self.assertEqual(self.events, [])

    def test_plain_character_is_typed(self):
        self.runtime.send_key("a")

        self.assertEqual(self.events, [(0, "a", "STRING")])

    def test_unknown_modifier_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.runtime.send_key("hyper+a")

        self.assertEqual(self.events, [])


class FakeNode:
    def __init__(self, role, name="", accessible_id="", children=None):
        self.role = role
        self.name = name
        self.accessible_id = accessible_id
        self.children = children or []

    def get_role_name(self):
        return self.role

    def get_name(self):
        return self.name

    def get_accessible_id(self):
        return self.accessible_id

    def get_child_count(self):
        return len(self.children)

    def get_child_at_index(self, index):
        return self.children[index]

    def get_component_iface(self):
        return None


def save_record(index=7):
    return {
        "index": index,
        "runtimeId": [0, 0],
        "automationId": "",
        "name": "Save",
        "controlType": "push button",
        "frame": None,
    }


class RuntimeStaleElementTests(unittest.TestCase):
    def setUp(self):
        self.runtime = load_runtime()

    def use_window(self, window):
        app = FakeNode("application", children=[window])
        self.runtime.main_window = lambda _app: (0, window)
        return app

    def test_path_that_now_points_at_another_element_is_rejected(self):
        # The Save dialog closed; the same child path [0, 0] now hits a menu item.
        window = FakeNode("frame", "~/t2.txt - Mousepad", children=[FakeNode("menu item", "DPatch")])
        app = self.use_window(window)

        self.assertIsNone(self.runtime.find_element(app, save_record()))

    def test_element_from_another_window_is_stale(self):
        # GTK keeps the closed Save dialog alive at window index 1; its button
        # still resolves but must not be clicked while window 0 is active.
        dialog = FakeNode("dialog", "Save As", children=[FakeNode("push button", "Save")])
        main = FakeNode("frame", "*Untitled 1 - Mousepad")
        app = FakeNode("application", children=[main, dialog])
        self.runtime.main_window = lambda _app: (0, main)
        record = dict(save_record(), runtimeId=[1, 0])

        self.assertIsNone(self.runtime.find_element(app, record))

    def test_element_found_again_after_reorder(self):
        save = FakeNode("push button", "Save")
        window = FakeNode("dialog", "Save As", children=[FakeNode("push button", "Cancel"), save])
        app = self.use_window(window)

        self.assertIs(self.runtime.find_element(app, save_record()), save)

    def test_truncated_name_matches_prefix(self):
        node = FakeNode("label", "x" * 600)
        record = {"controlType": "label", "name": "x" * 500 + "..."}

        self.assertTrue(self.runtime.record_matches(node, record, None))

    def test_role_mismatch_is_rejected(self):
        record = {"controlType": "push button", "name": "Save"}

        self.assertFalse(self.runtime.record_matches(FakeNode("menu item", "Save"), record, None))

    def test_stale_element_error_names_the_element(self):
        message = str(self.runtime.stale_element_error(save_record(137)))

        self.assertIn("137", message)
        self.assertIn("push button 'Save'", message)
        self.assertIn("get_app_state", message)


class RuntimeSettleTests(unittest.TestCase):
    def setUp(self):
        self.runtime = load_runtime()
        self.now = 0.0

    def clock(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds

    def test_returns_once_two_consecutive_signatures_match(self):
        frames = iter(["dialog", "closing", "main", "main", "never"])

        settled = self.runtime.wait_for_ui_settle(
            "app", clock=self.clock, sleep=self.sleep, signature=lambda _q: next(frames)
        )

        self.assertTrue(settled)
        self.assertLess(self.now, self.runtime.SETTLE_TIMEOUT_SECONDS)

    def test_lookup_error_stops_waiting_so_caller_can_reread(self):
        frames = iter([("main",), ("error", "appNotFound")])

        settled = self.runtime.wait_for_ui_settle(
            "app", clock=self.clock, sleep=self.sleep, signature=lambda _q: next(frames)
        )

        self.assertFalse(settled)
        self.assertLess(self.now, self.runtime.SETTLE_TIMEOUT_SECONDS)

    def test_gives_up_after_timeout_when_ui_keeps_changing(self):
        counter = iter(range(1000))

        settled = self.runtime.wait_for_ui_settle(
            "app", clock=self.clock, sleep=self.sleep, signature=lambda _q: next(counter)
        )

        self.assertFalse(settled)
        self.assertGreaterEqual(self.now, self.runtime.SETTLE_TIMEOUT_SECONDS)


if __name__ == "__main__":
    unittest.main()
