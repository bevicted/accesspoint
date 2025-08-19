use ratatui::{
    Frame,
    crossterm::event::{self, Event},
};

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut terminal = ratatui::init();

    let result = loop {
        terminal.draw(render)?;
        if matches!(event::read()?, Event::Key(_)) {
            break Ok(());
        }
    };

    ratatui::restore();
    result
}

fn render(frame: &mut Frame) {
    frame.render_widget("hello world", frame.area());
}
