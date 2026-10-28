// Integer hash for notiflight.frag (and dev/harness/hash-probe.frag), mirrored
// bit for bit by wang() and cellHash() in notiflight.js.
//
// Every constant is below 2^31: qsb rejects a uint literal that turns negative
// as an int ("Tried to convert uint literal into int"), which rules out PCG's
// 2891336453u. Wang's hash is cheap, not a high-quality generator.

uint wang(uint x) {
    x = (x ^ 61u) ^ (x >> 16u);
    x *= 9u;
    x ^= x >> 4u;
    x *= 668265261u;
    x ^= x >> 15u;
    return x;
}

// uint(int) wraps, so negative cells are defined.
uint cellHash(ivec2 c, uint salt) {
    return wang(uint(c.x) ^ wang(uint(c.y) ^ wang(salt)));
}

// Bytes 0..3 of h as 0..1; wang(h) gives bytes 4..7.
float byteOf(uint h, uint i) {
    return float((h >> (8u * i)) & 255u) * (1.0 / 255.0);
}
