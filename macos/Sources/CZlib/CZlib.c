#include "CZlib.h"
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

int loomings_raw_deflate(const uint8_t *input, size_t input_len,
                         uint8_t **output, size_t *output_len) {
    if (!output || !output_len) return -1;
    *output = NULL;
    *output_len = 0;

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                     -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return -1;
    }

    size_t capacity = deflateBound(&stream, (uLong)input_len);
    if (capacity < 64) capacity = 64;
    uint8_t *buffer = (uint8_t *)malloc(capacity);
    if (!buffer) {
        deflateEnd(&stream);
        return -1;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_len;
    stream.next_out = buffer;
    stream.avail_out = (uInt)capacity;

    int result;
    do {
        if (stream.avail_out == 0) {
            size_t next = capacity * 2;
            uint8_t *grown = (uint8_t *)realloc(buffer, next);
            if (!grown) {
                free(buffer);
                deflateEnd(&stream);
                return -1;
            }
            buffer = grown;
            stream.next_out = buffer + capacity;
            stream.avail_out = (uInt)(next - capacity);
            capacity = next;
        }
        result = deflate(&stream, Z_FINISH);
    } while (result == Z_OK);

    if (result != Z_STREAM_END) {
        free(buffer);
        deflateEnd(&stream);
        return -1;
    }

    *output = buffer;
    *output_len = (size_t)stream.total_out;
    deflateEnd(&stream);
    return 0;
}

int loomings_raw_inflate(const uint8_t *input, size_t input_len,
                         uint8_t **output, size_t *output_len,
                         size_t max_output) {
    if (!output || !output_len) return -1;
    *output = NULL;
    *output_len = 0;

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -15) != Z_OK) {
        return -1;
    }

    size_t capacity = input_len * 4 + 1024;
    if (capacity < 1024) capacity = 1024;
    if (capacity > max_output) capacity = max_output;
    if (capacity == 0) {
        inflateEnd(&stream);
        return -2;
    }

    uint8_t *buffer = (uint8_t *)malloc(capacity);
    if (!buffer) {
        inflateEnd(&stream);
        return -1;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_len;
    stream.next_out = buffer;
    stream.avail_out = (uInt)capacity;

    int result;
    do {
        if (stream.avail_out == 0) {
            if (capacity >= max_output) {
                free(buffer);
                inflateEnd(&stream);
                return -2;
            }
            size_t next = capacity * 2;
            if (next > max_output) next = max_output;
            uint8_t *grown = (uint8_t *)realloc(buffer, next);
            if (!grown) {
                free(buffer);
                inflateEnd(&stream);
                return -1;
            }
            buffer = grown;
            stream.next_out = buffer + capacity;
            stream.avail_out = (uInt)(next - capacity);
            capacity = next;
        }
        result = inflate(&stream, Z_NO_FLUSH);
        if (result == Z_NEED_DICT || result == Z_DATA_ERROR || result == Z_MEM_ERROR) {
            free(buffer);
            inflateEnd(&stream);
            return -1;
        }
        if (result == Z_BUF_ERROR && stream.avail_out > 0) {
            free(buffer);
            inflateEnd(&stream);
            return -1;
        }
    } while (result != Z_STREAM_END);

    *output = buffer;
    *output_len = (size_t)stream.total_out;
    inflateEnd(&stream);
    return 0;
}

void loomings_free(void *pointer) {
    free(pointer);
}
