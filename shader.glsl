vec3 evaluateSH(vec3 sh[9], vec3 n) {
  return max(
    .88622692545276 * sh[0] +
    1.0233267079465 * sh[1] * n.y +
    1.0233267079465 * sh[2] * n.z +
    1.0233267079465 * sh[3] * n.x +
    .85808553080978 * sh[4] * n.x * n.y +
    .85808553080978 * sh[5] * n.y * n.z +
    .24770795610038 * sh[6] * (3 * n.z * n.z - 1) +
    .85808553080978 * sh[7] * n.x * n.z +
    .42904276540489 * sh[8] * (n.x * n.x - n.y * n.y),
    0
  );
}
