# cython: language_level=3
# cython: cdivision=True
from libc.stdint cimport uint8_t, uint32_t


cdef extern from "rucfs.h" nogil:
    ctypedef enum rucfs_errcode_t:
        ok "rucfs_err_ok"
        arguments "rucfs_err_arguments"
        data_broken "rucfs_err_data_broken"
        unsupported "rucfs_err_unsupported"
        notfound "rucfs_err_notfound"
        out_of_memory "rucfs_err_out_of_memory"

    ctypedef uint8_t rucfs_inode_type_t
    uint8_t rucfs_inode_directory
    uint8_t rucfs_inode_file
    uint8_t rucfs_inode_symlink
    ctypedef uint32_t rucfs_flags_t
    int rucfs_flag_endian_be
    ctypedef struct rucfs_superblock_t:
        char magic[6]
        uint8_t version_major
        uint8_t version_minor
        uint32_t modded_time
        rucfs_flags_t flags
        uint32_t inode_table
        uint32_t data_table
        uint32_t string_table
        uint32_t reserved

    ctypedef struct rucfs_inode_t:
        rucfs_inode_type_t type
        uint32_t name_offset

    ctypedef struct rucfs_inode_directory_t:
        rucfs_inode_t common
        uint32_t item_count
        uint32_t ref_inode_offset

    ctypedef struct rucfs_inode_file_t:
        rucfs_inode_t common
        uint32_t data_offset
        uint32_t data_length

    ctypedef struct rucfs_inode_symlink_t:
        rucfs_inode_t common
        uint32_t ref_inode_offset

    ctypedef struct rucfs_ctx_t:
        uint8_t * itab
        uint8_t * dattab
        uint8_t * strtab
        rucfs_inode_directory_t * rootdir

    ctypedef struct rucfs_file_t:
        char * name
        uint8_t * data
        uint32_t length

    ctypedef struct rucfs_path_enum_t:
        rucfs_inode_type_t type
        char * name

    bint rucfs_ok(rucfs_errcode_t e)
    int RUCFS_DEFAULT
    # macro
    rucfs_inode_t *rucfs_open_symlink(rucfs_ctx_t * ctx, rucfs_inode_symlink_t * inode)
    rucfs_inode_t *rucfs_open_directory(rucfs_ctx_t * ctx, rucfs_inode_directory_t * inode)
    char*  rucfs_inode_name(rucfs_ctx_t * ctx, rucfs_inode_t * inode)

    rucfs_errcode_t rucfs_load(uint8_t * data, rucfs_ctx_t * ctx)
    rucfs_errcode_t rucfs_path_to(rucfs_ctx_t * ctx, const char * file, rucfs_inode_t** inode)
    rucfs_errcode_t rucfs_fopen(rucfs_ctx_t * ctx, const char * file, rucfs_file_t** fp)
    rucfs_errcode_t rucfs_fclose(rucfs_file_t * fp)
    bint rucfs_exist(rucfs_ctx_t * ctx, const char * file, rucfs_errcode_t * err)
    rucfs_errcode_t rucfs_enumerate_path(rucfs_ctx_t * ctx, const char * path, rucfs_path_enum_t * list_, size_t * size)
    size_t rucfs_normalize_path(char * dst, const char * src, bint endslash)
