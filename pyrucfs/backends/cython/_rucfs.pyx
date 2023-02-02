# cython: language_level=3
# cython: cdivision=True
cimport cython
from cpython.mem cimport PyMem_Free, PyMem_Malloc
from libc.stdint cimport uint8_t, uint32_t

from pyrucfs.backends.cython.rucfs cimport (rucfs_ctx_t, rucfs_enumerate_path,rucfs_inode_name,rucfs_open_directory,rucfs_path_to,
                                            rucfs_fclose, rucfs_file_t,rucfs_open_symlink,rucfs_inode_symlink_t,rucfs_exist,
                                            rucfs_fopen, rucfs_inode_directory,rucfs_inode_directory_t,
                                            rucfs_inode_file,rucfs_inode_t,
                                            rucfs_inode_symlink, rucfs_ok,rucfs_errcode_t,
                                            rucfs_path_enum_t,rucfs_load,
                                            rucfs_superblock_t,rucfs_normalize_path)


@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class SuperBlock:
    cdef rucfs_superblock_t * _block

    def __cinit__(self):
        self._block = <rucfs_superblock_t *> PyMem_Malloc(sizeof(rucfs_superblock_t))
        if not self._block:
            raise MemoryError

    def __dealloc__(self):
        if self._block:
            PyMem_Free(self._block)
            self._block = NULL

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class File:
    cdef:
        Py_ssize_t view_count
        Py_ssize_t shape[1]
        Py_ssize_t strides[1]
        rucfs_file_t* file

    @staticmethod
    cdef inline File from_ptr(rucfs_file_t* file):
        cdef File self = File.__new__(File)
        self.file = file
        self.view_count = 0
        self.strides[0] = 1
        return self

    @property
    def name(self):
        return <bytes>self.file.name

    cpdef inline close(self):
        if not rucfs_ok(rucfs_fclose(self.file)):
            raise IOError

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def __len__(self):
        return self.file.length

    # buffer protocol
    def __getbuffer__(self, Py_buffer * buffer, int flags):
        self.view_count += 1
        self.shape[0] = <Py_ssize_t> self.file.length
        cdef size_t itemsize = sizeof(uint8_t)
        buffer.buf = self.file.data
        buffer.obj = self
        buffer.len = self.shape[0] * itemsize
        buffer.readonly = 0
        buffer.itemsize = <Py_ssize_t> itemsize
        buffer.format = "B"
        buffer.ndim = 1
        buffer.shape = self.shape
        buffer.strides = self.strides
        buffer.suboffsets = NULL

    def __releasebuffer__(self, Py_buffer * buffer):
        self.view_count -= 1

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Path:
    cdef rucfs_path_enum_t* path

    @staticmethod
    cdef inline Path from_ptr(rucfs_path_enum_t* path):
        cdef Path self = Path.__new__(Path)
        self.path = path
        return self

    @property
    def name(self):
        return <bytes> self.path.name

    @property
    def type(self):
        """
        directory or file or symlink
        """
        if self.path.type == rucfs_inode_directory:
            return "directory"
        elif    self.path.type == rucfs_inode_file:
            return "file"
        elif  self.path.type == rucfs_inode_symlink:
            return "symlink"
@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Inode:
    cdef rucfs_inode_t *node

    @staticmethod
    cdef inline Inode from_ptr(rucfs_inode_t *node):
        cdef Inode self = Inode.__new__(Inode)
        self.node = node
        return self

    @property
    def type(self):
        """
        directory or file or symlink
        """
        if self.node.type == rucfs_inode_directory:
            return "directory"
        elif self.node.type == rucfs_inode_file:
            return "file"
        elif self.node.type == rucfs_inode_symlink:
            return "symlink"

    @property
    def name_offset(self):
        return self.node.name_offset
@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Directory:
    cdef rucfs_inode_directory_t* d

    @staticmethod
    cdef inline Directory from_ptr(rucfs_inode_directory_t* d):
        cdef Directory self = Directory.__new__(Directory)
        self.d = d
        return self

    @property
    def common(self):
        return Inode.from_ptr(&self.d.common)

    @property
    def item_count(self):
        return self.d.item_count

    @property
    def ref_inode_offset(self):
        return self.d.ref_inode_offset

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Symlink:
    cdef rucfs_inode_symlink_t* _link
    @staticmethod
    cdef inline Symlink from_ptr(rucfs_inode_symlink_t* link):
        cdef Symlink self =Symlink.__new__(Symlink)
        self._link = link
        return self

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Context:
    cdef rucfs_ctx_t * _ctx

    def __cinit__(self):
        self._ctx = <rucfs_ctx_t *> PyMem_Malloc(sizeof(rucfs_ctx_t))
        if not self._ctx:
            raise MemoryError

    def __dealloc__(self):
        if self._ctx:
            PyMem_Free(self._ctx)
            self._ctx = NULL

    cpdef File fopen(self, const uint8_t[::1] path):
        cdef rucfs_file_t* file
        cdef rucfs_errcode_t code
        with nogil:
            code = rucfs_fopen(self._ctx, <const char *>&path[0], &file)
        if not rucfs_ok(code):
            raise FileNotFoundError
        return File.from_ptr(file)

    cpdef inline Inode open_symlink(self, Symlink link):
        cdef rucfs_inode_t * node
        with nogil:
            node = rucfs_open_symlink(self._ctx, link._link)
        return Inode.from_ptr(node)

    cpdef inline Inode open_directory(self, Directory d):
        cdef rucfs_inode_t * node
        with nogil:
            node = rucfs_open_directory(self._ctx, d.d)
        return Inode.from_ptr(node)

    cpdef inline  Inode path_to(self, const uint8_t[::1] path):
        cdef:
            rucfs_inode_t* node
            rucfs_errcode_t code
        with nogil:
            code = rucfs_path_to(self._ctx, <const char *> &path[0], &node)
        if not rucfs_ok(code):
            raise IOError
        return Inode.from_ptr(node)

    cpdef inline bint exist(self, const uint8_t[::1] path):
        cdef:
            rucfs_errcode_t  err
            bint code = False
        with nogil:
            code = rucfs_exist(self._ctx, <const char *> &path[0], &err)
        if not rucfs_ok(err):
            raise IOError
        return code

    cpdef bytes inode_name(self,  Inode node):
        return  <bytes>rucfs_inode_name(self._ctx, node.node)

    def enumerate_path(self, const uint8_t[::1] path):
        """
        path like a/b/c
        :param path:
        :return:
        """
        cdef size_t size, i
        # count files
        cdef rucfs_path_enum_t* list_
        cdef rucfs_errcode_t code
        with nogil:
            code = rucfs_enumerate_path(self._ctx, <const char *> &path[0], NULL, &size)
        if not rucfs_ok(code):
            raise IOError

        list_ = <rucfs_path_enum_t*>PyMem_Malloc(sizeof(rucfs_path_enum_t) * size)
        if not list_:
            raise MemoryError
        try:
            with nogil:
                code = rucfs_enumerate_path(self._ctx, <const char *>&path[0], list_, &size)
                if not rucfs_ok(code):
                    raise IOError
            for i in range(size):
                yield Path.from_ptr( &list_[i])
        finally:
            PyMem_Free(list_)

    @staticmethod
    def load(const uint8_t[::1] data):
        """
        keep a refcount to data!
        :param data:
        :return:
        """
        cdef Context self = Context()
        cdef rucfs_errcode_t code
        with nogil:
            code = rucfs_load(<uint8_t*>&data[0],self._ctx)
        if not rucfs_ok(code):
            raise IOError
        return self

    @property
    def rootdir(self):
        return Directory.from_ptr( self._ctx.rootdir)

cpdef inline size_t normalize_path(uint8_t[::1] buf, const uint8_t[::1] s, bint endslash) nogil:
    return rucfs_normalize_path(<char*>&buf[0],<const char*>&s[0], endslash)
