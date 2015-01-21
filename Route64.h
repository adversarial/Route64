#pragma once

/*
    Route64 API
        by ~vividrev
        
    Implements several routines to "break  through" the WoW64 layer.
 */
#include <stdint.h>

#ifndef _M_IX86
#error "Only x86-32 is valid for Route64 library"
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Calls a function in x64 mode with stdcall convention using rcx, rdx, r8, r9, ...
// Returns false if not in WoW64 mode (x64 not available)
bool __stdcall WoW64Stdcallx64(uintptr_t CalleeHigh, uintptr_t CalleeLow, 
                               uintptr_t* RetValHigh, uintptr_t* RetValLow, 
                               uint args_cb, uint64_t* args);

// Copies memory to/from 64 bit addresses
// Returns bytes copied
size_t __stdcall WoW64CopyMemory(uintptr_t DestHigh, uintptr_t DestLow, 
                                 uintptr_t SrcHigh, uintptr_t SrcLow, 
                                 size_t cbHigh, size_t cbLow);
                              
#ifdef __cplusplus
}
#endif
