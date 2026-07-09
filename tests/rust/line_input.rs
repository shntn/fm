use fm::line_input;
use mlua::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

mod register {
    use super::*;

    #[test]
    fn request_line_input_records_the_request() {
        let lua = Lua::new();
        let pending = Rc::new(RefCell::new(None));
        line_input::register(&lua, pending.clone()).unwrap();

        lua.load(r#"terminal.request_line_input(0, 23, 80, "/")"#)
            .exec()
            .unwrap();

        let request = pending.borrow_mut().take().unwrap();
        assert_eq!(0, request.x);
        assert_eq!(23, request.y);
        assert_eq!(80, request.max_width);
        assert_eq!("/", request.prompt);
    }

    #[test]
    fn no_request_is_recorded_when_not_called() {
        let lua = Lua::new();
        let pending = Rc::new(RefCell::new(None));
        line_input::register(&lua, pending.clone()).unwrap();

        assert!(pending.borrow().is_none());
    }

    #[test]
    fn taking_the_pending_request_clears_it() {
        let lua = Lua::new();
        let pending = Rc::new(RefCell::new(None));
        line_input::register(&lua, pending.clone()).unwrap();

        lua.load(r#"terminal.request_line_input(0, 0, 10, "/")"#)
            .exec()
            .unwrap();
        pending.borrow_mut().take();

        assert!(pending.borrow().is_none());
    }
}
