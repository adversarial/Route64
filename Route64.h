#pragma once

#include <stdint.h>

#ifndef _M_IX86
#error "Only x86-32 is valid for Route64 library"
#endif

typedef void* (__stdcall *stdcall_f)();

void* __stdcall WoW64Stdcallx64(stdcall_f AddrLow, stdcall_f AddrHigh,
                                    unsigned int args_cb, void** args);

uint32_t __stdcall WoW64Write(void* DestLow, void* DestHigh,
                              const void* Src, size_t cbSrc);

uint32_t __stdcall WoW64Read(const void* SrcLow, const void* SrcHigh,
                             void* Dest, size_t cbDest);