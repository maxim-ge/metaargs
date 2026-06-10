sealed class Result<T, E> {}

final class Ok<T, E> extends Result<T, E> {
  final T v;
  Ok(this.v);
}

final class Err<T, E> extends Result<T, E> {
  final E e;
  Err(this.e);
}

sealed class Option<T> {}

final class Some<T> extends Option<T> {
  final T v;
  Some(this.v);
}

final class None<T> extends Option<T> {}
