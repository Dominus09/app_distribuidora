String formatearPesosChilenos(int valor) {
  final s = valor.toString();
  final b = StringBuffer(r'$');
  var pos = 0;
  final rem = s.length % 3;
  if (rem > 0) {
    b.write(s.substring(0, rem));
    pos = rem;
    if (pos < s.length) b.write('.');
  }
  while (pos < s.length) {
    b.write(s.substring(pos, pos + 3));
    pos += 3;
    if (pos < s.length) b.write('.');
  }
  return b.toString();
}
