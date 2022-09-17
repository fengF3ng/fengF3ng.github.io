---
title: dl_runtime_resolve解析
date: 2022-09-15 16:20:00 +0800
categories: [Linux, Basic]
tags: [linux, basic, compile]     # TAG names should always be lowercase
---

# _dl_runtime_resolve

位于loader中，用于解析外部函数符号的函数，解析完成后会直接执行解析的函数。

被PLT[0]调用时需要传入link_map和reloc_arg参数，紧接着将这些参数传入_dl_fixup进行解析。

```asm
# glibc/sysdeps/i386/dl-trampoline.S
_dl_runtime_resolve:
	cfi_adjust_cfa_offset (8)
	_CET_ENDBR
	pushl %eax		# Preserve registers otherwise clobbered.
	cfi_adjust_cfa_offset (4)
	pushl %ecx
	cfi_adjust_cfa_offset (4)
	pushl %edx
	cfi_adjust_cfa_offset (4)
	movl 16(%esp), %edx	# Copy args pushed by PLT in register.  Note
	movl 12(%esp), %eax	# that `fixup' takes its parameters in regs.
	call _dl_fixup		# Call resolver.
	popl %edx		# Get register content back.
	cfi_adjust_cfa_offset (-4)
	movl (%esp), %ecx
	movl %eax, (%esp)	# Store the function address.
	movl 4(%esp), %eax
	ret $12			# Jump to function address.
```

# link_map

动态链接器映射到内存中时，首先会处理自身的重定位，因为链接器本身就是一个共享库。接着会查看可执行程序的动态段并查找DT_NEEDED参数，该参数保存了指向所需要的共享库的字符串或者路径名。当一个共享库被映射到内存之后，链接器会获取到共享库的动态段，并将共享库的符号表添加到符号链中，符号链存储了所有映射到内存中的共享库的符号表。

链接器为每个共享库生成一个link_map结构的条目，并将其存到一个链表中

```c
// /usr/include/link.h
struct link_map
  {
    /* These first few members are part of the protocol with the debugger.
       This is the same format used in SVR4.  */

    ElfW(Addr) l_addr;		/* Difference between the address in the ELF
				   file and the addresses in memory.  */
    char *l_name;		/* Absolute file name object was found in.  */
    ElfW(Dyn) *l_ld;		/* Dynamic section of the shared object.  */
    struct link_map *l_next, *l_prev; /* Chain of loaded objects.  */
  };
```

# _dl_fixup

1. 通过参数reloc_arg计算.rel.plt对应的Elf32_Rel结构体。
2. 通过reloc->r_info找到.dynsym中对应的Elf32_Sym结构体
3. 通过sym->st_name+dynstr找到符号表字符串，通过_dl_lookup_symbol寻找libc基地址并返回给result。DL_FIXUP_MAKE_VALUE得到的value为libc基址加上要解析函数的偏移地址即实际地址
4. 最后把value写回相应的GOT表项(*(reloc->r_offset))中

```c
// glibc/elf/dl-runtime.c
DL_FIXUP_VALUE_TYPE
attribute_hidden __attribute ((noinline)) DL_ARCH_FIXUP_ATTRIBUTE
_dl_fixup (
# ifdef ELF_MACHINE_RUNTIME_FIXUP_ARGS
	   ELF_MACHINE_RUNTIME_FIXUP_ARGS,
# endif
	   struct link_map *l, ElfW(Word) reloc_arg)
{
  const ElfW(Sym) *const symtab
    = (const void *) D_PTR (l, l_info[DT_SYMTAB]);
  const char *strtab = (const void *) D_PTR (l, l_info[DT_STRTAB]);

  const uintptr_t pltgot = (uintptr_t) D_PTR (l, l_info[DT_PLTGOT]);

// 1. 通过参数reloc_arg计算.rel.plt对应的Elf32_Rel结构体
//    JMPREL即.rel.plt
  const PLTREL *const reloc
    = (const void *) (D_PTR (l, l_info[DT_JMPREL])
		      + reloc_offset (pltgot, reloc_arg));
// 2. 找到.dynsym中对应的Elf32_Sym结构体
  const ElfW(Sym) *sym = &symtab[ELFW(R_SYM) (reloc->r_info)];
  const ElfW(Sym) *refsym = sym;
  void *const rel_addr = (void *)(l->l_addr + reloc->r_offset);
  lookup_t result;
  DL_FIXUP_VALUE_TYPE value;

  /* Sanity check that we're really looking at a PLT relocation.  */
  assert (ELFW(R_TYPE)(reloc->r_info) == ELF_MACHINE_JMP_SLOT);

   /* Look up the target symbol.  If the normal lookup rules are not
      used don't look in the global scope.  */
  if (__builtin_expect (ELFW(ST_VISIBILITY) (sym->st_other), 0) == 0)
    {
      const struct r_found_version *version = NULL;

      if (l->l_info[VERSYMIDX (DT_VERSYM)] != NULL)
	{
	  const ElfW(Half) *vernum =
	    (const void *) D_PTR (l, l_info[VERSYMIDX (DT_VERSYM)]);
	  ElfW(Half) ndx = vernum[ELFW(R_SYM) (reloc->r_info)] & 0x7fff;
	  version = &l->l_versions[ndx];
	  if (version->hash == 0)
	    version = NULL;
	}

      /* We need to keep the scope around so do some locking.  This is
	 not necessary for objects which cannot be unloaded or when
	 we are not using any threads (yet).  */
      int flags = DL_LOOKUP_ADD_DEPENDENCY;
      if (!RTLD_SINGLE_THREAD_P)
	{
	  THREAD_GSCOPE_SET_FLAG ();
	  flags |= DL_LOOKUP_GSCOPE_LOCK;
	}

// 3. 通过_dl_lookup_symbol寻找libc基地址并返回给result
//    sym->st_name即函数名
      result = _dl_lookup_symbol_x (strtab + sym->st_name, l, &sym, l->l_scope,
				    version, ELF_RTYPE_CLASS_PLT, flags, NULL);

      /* We are done with the global scope.  */
      if (!RTLD_SINGLE_THREAD_P)
	THREAD_GSCOPE_RESET_FLAG ();


      /* Currently result contains the base load address (or link map)
	 of the object that defines sym.  Now add in the symbol
	 offset.  */
// 3. libc基址加上要解析函数的偏移地址即实际地址
      value = DL_FIXUP_MAKE_VALUE (result,
				   SYMBOL_ADDRESS (result, sym, false));
    }
  else
    {
      /* We already found the symbol.  The module (and therefore its load
	 address) is also known.  */
      value = DL_FIXUP_MAKE_VALUE (l, SYMBOL_ADDRESS (l, sym, true));
      result = l;
    }

  /* And now perhaps the relocation addend.  */
  value = elf_machine_plt_value (l, reloc, value);

  if (sym != NULL
      && __builtin_expect (ELFW(ST_TYPE) (sym->st_info) == STT_GNU_IFUNC, 0))
    value = elf_ifunc_invoke (DL_FIXUP_VALUE_ADDR (value));
...
  /* Finally, fix up the plt itself.  */
  if (__glibc_unlikely (GLRO(dl_bind_not)))
    return value;

// 4. 把value写回相应的GOT表项(*(reloc->r_offset))中
  return elf_machine_fixup_plt (l, result, refsym, sym, reloc, rel_addr, value);
}

```

![Window shadow](/assets/img/2022-09/2022-09-15-dl_runtime_resolve%E8%A7%A3%E6%9E%90/dl_fixup.drawio.svg){: .shadow}
_dl_fixup调用过程_

# reference

1. [_dl_runtime_resolve](https://www.jianshu.com/p/57f6474fe4c6)
2. [dl-resolve浅析](https://xz.aliyun.com/t/6364)