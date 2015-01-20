;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Implements several routines to "break  through" the WoW64 layer.
;; by ~vividrev
;;
;; 1/20/15:
;;      0.2: Refactored
;; 12/3/14:
;;      0.1: It works
;;
; todo list:
; [x]   refactor
; [x]   fix internal errors (register scrapping)
; [ ]   debug

include '%inc%\win32a.inc'
format MS COFF

CS_MODE_WOW64 = $23
CS_MODE_NATIVE_AMD64 = $33


public WoW64CopyMemory as '_WoW64CopyMemory@24'
public WoW64Stdcall64 as '_WoW64Stdcall64@16'

;======= Code ===================================
section '.text' code readable executable align 16
;================================================
; size_t __stdcall xx(uintptr_t DestHigh, uintptr_t DestLow, uintptr_t SrcHigh, uintptr_t SrcLow, size_t cbHigh, size_t cbLow)
WoW64CopyMemory:
use32
    lea ecx, [esp+4]    ; &args[0]
    push edi
    
    sub esp, 8
    mov eax, esp; retval*
    
    stdcall _x64CopyMemory, 0, eax, 0, 4*6, ecx
    
    pop eax     ; retval hi
    pop eax     ; retval lo
    
    pop edi
    ret 4*6

; size_t __stdcall xx(void* Dest, void* Src, size_t cb)
_x64CopyMemory:
use64
    mov rax, rdi
    mov rdi, rdx
    mov rdx, rsi
    mov rsi, rcx
    mov rcx, r8
    
    cld
    rep movsb
    sub r8, rcx     ; difference of needed : unwritten
 
    mov rdi, rax
    mov rsi, rdx
    mov rax, r8
    ret 8*4
    

; bool __stdcall xx(uintptr_t AddrHigh, uintptr_t AddrLow, uintptr_t* RetHigh, uintptr_t* RetLow, uint args_cb, uint64_t* args)
WoW64Stdcall64:
use32
    push ebp edi esi ebx
    
    mov eax, cs
    cmp eax, CS_MODE_WOW64
    xor eax, eax
    jne .Done
    
    ; setup args
    mov ecx, [esp+4*4+4+4*2]    ; args_cb
    shr ecx, 2                  ; args_cb / sizeof(word) = num_arg_words
    mov esi, [esp+4*4+4+4*3]    ; &args[]
    lea esi, [esi+ecx*8-8]      ; end of args, copy in reverse order
    
    lea ebp, [esp+4*4+4+4*0]    ; AddrHigh, AddLow, RetHigh, RetLow
    
    ; setup stack
    sub esp, 8*3                ; uint64_t SavedRegisters[3], ensure minimum padding
    mov eax, esp
    and eax, 7                  ; check if bits need to be aligned
    xor eax, 7                  ; flip alignment bits to get inverse
    add eax, 1
    add esp, eax                ; align to 8
    
    ; pass args
    push eax                    ; align lo
    push 0                      ; align hi
    std                         ; push args last-first
 
    mov edx, ecx
  @@:   
    lodsd                       ; get next arg *(uint32_t*)args++
    push eax
    sub ecx, 1
    ja @b

    ; our implicit args
    mov eax, [ebp+4*1]      ; Callee
    push eax
    mov eax, [ebp+4*0]
    push eax
    mov eax, [ebp+4*3]      ; RetVal*
    push eax
    mov eax, [ebp+4*2]
    push eax
    push edx                ; NumArgs
    push 0
    
    ; far call pushes 2 dwords, { RetAddr, RetSegment }
    call CS_MODE_NATIVE_AMD64:_HeavensGate
    add esp, 4          ; align hi
    pop eax             ; align lo
    lea esp, [esp+eax+8*3]
    mov eax, 1          ; ERROR_SUCCESS
  .Done:    
    pop ebx esi edi ebp
    ret 4*4

; PRIVATE void xx(Farcall Return, uint NumArgs, uint* Retval, uintptr Callee, ...)
_HeavensGate:
align 16
use64
    ; save registers to preserve passed args for stack transplant
    mov rcx, [rsp+8]            ; NumArgs
    lea rax, [rsp+rcx*8+8*4]    ; &SavedRegisters[3]
    mov [rax+8*0], rdi
    mov [rax+8*1], rsi
    mov [rax+8*2], rbx

    pop rbx             ; dword[] { RetAddr, RetSegment }
    pop rax             ; NumArgs
    pop rdi             ; RetVal ptr
    pop rsi             ; Callee

    test rax, rax
    jna @f
    pop rcx
    sub rax, 1
    jna @f
    pop rdx
    sub rax, 1
    jna @f
    pop r8
    sub rax, 1
    jna @f
    pop r9

  @@:
    sub rsp, 8*4        ; arg scratch space
    call rsi

    mov [rdi], rax      ; save return val in 32bit accessible
    mov rax, rbx        ; dword[] { RetAddr, RetSegment }
    mov rdi, [rsp+8+8*0] 
    mov rsi, [rsp+8+8*1]
    mov rbx, [rsp+8+8*2]
    push rax
    retf
    
