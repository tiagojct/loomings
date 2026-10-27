#ifndef CZLIB_H
#define CZLIB_H

#include <stddef.h>
#include <stdint.h>

/// Raw DEFLATE (RFC 1951, no zlib header/checksum). Returns 0 on success.
int loomings_raw_deflate(const uint8_t *input, size_t input_len,
                         uint8_t **output, size_t *output_len);

/// Raw DEFLATE inflate with an explicit output cap. Returns -2 when the cap
/// would be exceeded.
int loomings_raw_inflate(const uint8_t *input, size_t input_len,
                         uint8_t **output, size_t *output_len,
                         size_t max_output);

void loomings_free(void *pointer);

#endif
