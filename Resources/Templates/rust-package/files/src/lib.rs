pub fn greeting(name: &str) -> String {
    format!("Hello, {name}!")
}

#[cfg(test)]
mod tests {
    use super::greeting;

    #[test]
    fn greeting_mentions_name() {
        assert_eq!(greeting("Cocxy"), "Hello, Cocxy!");
    }
}
