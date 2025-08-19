use ratatui::{
    Frame,
    crossterm::event::{self, Event},
};
use toml::Table;

mod cli;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = cli::parse();

    println!("{:?}", args);

    if args.is_validation {
        std::process::exit(0);
    }

    let terminal = ratatui::init();
    let result = run(terminal);

    ratatui::restore();

    result
}

fn run(mut terminal: ratatui::DefaultTerminal) -> Result<(), Box<dyn std::error::Error>> {
    loop {
        terminal.draw(render)?;
        if matches!(event::read()?, Event::Key(_)) {
            break Ok(());
        }
    }
}

fn render(frame: &mut Frame) {
    frame.render_widget("hello world", frame.area());
}
