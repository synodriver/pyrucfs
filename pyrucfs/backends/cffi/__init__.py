"""
Copyright (c) 2008-2022 synodriver <synodriver@gmail.com>
"""
from pyrucfs.backends.cffi._rucfs import ffi, lib

INODE_DIRECTORY = lib.rucfs_inode_directory
INODE_FILE = lib.rucfs_inode_file
INODE_SYMLINK = lib.rucfs_inode_symlink


def path_to_str(p) -> str:
    """
    directory or file or symlink
    """
    if p.type == lib.rucfs_inode_directory:
        return "directory"
    elif p.type == lib.rucfs_inode_file:
        return "file"
    elif p.type == lib.rucfs_inode_symlink:
        return "symlink"
    else:
        return "unknown"


def check_err(err) -> str:
    if err == lib.rucfs_err_ok:
        return "ok"
    elif err == lib.rucfs_err_arguments:
        return "arguments"
    elif err == lib.rucfs_err_data_broken:
        return "data_broken"
    elif err == lib.rucfs_err_unsupported:
        return "unsupported"
    elif err == lib.rucfs_err_notfound:
        return "notfound"
    elif err == lib.rucfs_err_out_of_memory:
        return "out_of_memory"


class SuperBlock:
    """
    internal use
    """

    # cdef rucfs_superblock_t * _block

    def __init__(self):
        self._block = ffi.new("rucfs_superblock_t*")


class File:
    @staticmethod
    def from_ptr(file) -> "File":
        self = File.__new__(File)
        self.file = file
        return self

    @property
    def name(self):
        return ffi.string(self.file.name)

    def close(self):
        code = lib.rucfs_fclose(self.file)
        if not lib.rucfs_ok(code):
            raise IOError(check_err(code))

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def __len__(self):
        return self.file.length

    # buffer protocol
    def __bytes__(self):
        return ffi.unpack(ffi.cast("char*", self.file.data), self.file.length)


class Path:
    # cdef rucfs_path_enum_t* path

    def __init__(self):
        self.path = ffi.new("rucfs_path_enum_t*")

    @staticmethod
    def from_ptr(path) -> "Path":
        self = Path.__new__(Path)
        try:
            self.path[0] = path[0]  # perform a deepcopy
        except TypeError:
            # not a ptr
            self.path = path
        return self

    @property
    def name(self):
        return ffi.string(self.path.name)

    @property
    def type(self):
        """
        directory or file or symlink
        """
        return self.path.type

    def __str__(self):
        return f"Path: name = {self.name}, type = {path_to_str(self.path)}"

    __repr__ = __str__


class Inode:
    # cdef:
    #     rucfs_inode_t *node
    #     int own
    def __init__(
        self, type_=lib.rucfs_inode_directory, name_offset: int = 0, own: bool = True
    ):
        if own:
            self.node = ffi.new("rucfs_inode_t*")
            if not self.node:
                raise MemoryError
            self.node.type = type_
            self.node.name_offset = name_offset
            self.own = True
        else:
            self.own = False

    def __del__(self):
        if self.own and self.node:
            del self.node

    @staticmethod
    def from_ptr(node):
        self = Inode.__new__(Inode, own=False)
        self.node = node
        return self

    @property
    def type(self):
        """
        directory or file or symlink
        """
        return self.node.type

    @property
    def name_offset(self):
        return self.node.name_offset


class Directory:
    # cdef:
    #     rucfs_inode_directory_t* d
    #     int own

    def __init__(
        self,
        type_=lib.rucfs_inode_directory,
        name_offset: int = 0,
        item_count: int = 0,
        ref_inode_offset: int = 0,
        own: bool = True,
    ):
        if own:
            self.d = ffi.new("rucfs_inode_directory_t*")
            tmp = ffi.cast("rucfs_inode_t *", self.d)
            tmp.type = type_
            tmp.name_offset = name_offset
            self.d.item_count = item_count
            self.d.ref_inode_offset = ref_inode_offset
            self.own = True
        else:
            self.own = False

    def __del__(self):
        if self.own and self.d:
            del self.d

    @staticmethod
    def from_ptr(d) -> "Directory":
        self = Directory(own=False)
        self.d = d
        return self

    @property
    def common(self):
        return Inode.from_ptr(self.d.common)

    @property
    def item_count(self):
        return self.d.item_count

    @property
    def ref_inode_offset(self):
        return self.d.ref_inode_offset


class Symlink:
    # cdef:
    #     rucfs_inode_symlink_t* _link
    #     int own   # own this ptr (not from_ptr)

    def __init__(
        self,
        type_=lib.rucfs_inode_directory,
        name_offset: int = 0,
        ref_inode_offset: int = 0,
        own: bool = True,
    ):
        if own:  # user created struct
            self._link = ffi.new("rucfs_inode_symlink_t*")
            ffi.cast("rucfs_inode_t*", self._link).type = type_
            ffi.cast("rucfs_inode_t*", self._link).name_offset = name_offset
            self._link.ref_inode_offset = ref_inode_offset
            self.own = True
        else:  # from_ptr called
            self.own = False

    def __dealloc__(self):
        if self.own and self._link:
            del self._link

    @staticmethod
    def from_ptr(link) -> "Symlink":
        self = Symlink.__new__(Symlink, own=False)
        self._link = link
        return self

    @property
    def common(self):
        return Inode.from_ptr(self._link.common)

    @property
    def ref_inode_offset(self):
        return self._link.ref_inode_offset


class Context:
    # cdef:
    #     rucfs_ctx_t * _ctx
    #     const uint8_t[::1] data

    def __init__(self):
        self._ctx = ffi.new("rucfs_ctx_t*")

    def fopen(self, path: bytes) -> File:
        # cdef rucfs_file_t* file
        file = ffi.new("rucfs_file_t**")
        # cdef rucfs_errcode_t code = ok

        code = lib.rucfs_fopen(self._ctx, ffi.from_buffer(path), file)
        if not lib.rucfs_ok(code):
            raise IOError(check_err(code))
        return File.from_ptr(file[0])

    def open_symlink(self, link: Symlink) -> Inode:
        node = lib.rucfs_open_symlink(self._ctx, link._link)
        return Inode.from_ptr(node)

    def open_directory(self, d: Directory) -> Inode:
        # cdef rucfs_inode_t * node
        node = lib.rucfs_open_directory(self._ctx, d.d)
        return Inode.from_ptr(node)

    def path_to(self, path: bytes) -> Inode:
        # cdef:
        node = ffi.new("rucfs_inode_t**")
        code = lib.rucfs_path_to(self._ctx, ffi.from_buffer(path), node)
        if not lib.rucfs_ok(code):
            raise IOError(check_err(code))
        return Inode.from_ptr(node[0])

    def exist(self, path: bytes) -> bool:
        # cdef:
        err = ffi.new("rucfs_errcode_t*")
        #     rucfs_errcode_t err = ok
        #     bint code = False
        # with nogil:
        code = lib.rucfs_exist(self._ctx, ffi.from_buffer(path), err)
        if not lib.rucfs_ok(err[0]):
            raise IOError(check_err(err[0]))
        return code

    def __contains__(self, item):
        return self.exist(item)

    def inode_name(self, node: Inode) -> bytes:
        return ffi.string(lib.rucfs_inode_name(self._ctx, node.node))

    def enumerate_path(self, path: bytes):  # todo segfault
        """
        path like a/b/c
        :param path:
        :return:
        """
        # cdef size_t size, i
        size = ffi.new("size_t*")
        # count files
        # cdef rucfs_path_enum_t* list_
        # cdef rucfs_errcode_t code = ok
        # with nogil:
        code = lib.rucfs_enumerate_path(
            self._ctx, ffi.from_buffer(path), ffi.NULL, size
        )
        if not lib.rucfs_ok(code):
            raise IOError(check_err(code))
        tmp = ffi.new(f"char[{ffi.sizeof('rucfs_path_enum_t') * size[0]}]")
        list_ = ffi.cast("rucfs_path_enum_t*", tmp)

        # list_ = <rucfs_path_enum_t*>PyMem_Malloc(sizeof(rucfs_path_enum_t) * size[0])
        # if not list_:
        #     raise MemoryError
        # try:
        # with nogil:
        code = lib.rucfs_enumerate_path(
            self._ctx, ffi.from_buffer(path), list_, size
        )  # must from same thread
        if not lib.rucfs_ok(code):
            raise IOError(check_err(code))
        for i in range(size[0]):
            yield Path.from_ptr(list_[i])
        # finally:
        #     PyMem_Free(list_)

    @staticmethod
    def load(data: bytes):
        """
        todo! keep a refcount to data! should we do that?
        :param data:
        :return:
        """
        self = Context()
        self.data = data
        # cdef rucfs_errcode_t code = ok
        # with nogil:
        code = lib.rucfs_load(ffi.cast("uint8_t*", ffi.from_buffer(data)), self._ctx)
        if not lib.rucfs_ok(code):
            raise IOError(check_err(code))
        return self

    @property
    def rootdir(self):
        return Directory.from_ptr(self._ctx.rootdir)


def normalize_path(buf: bytearray, s: bytes, endslash: bool) -> int:
    return lib.rucfs_normalize_path(ffi.from_buffer(buf), ffi.from_buffer(s), endslash)
