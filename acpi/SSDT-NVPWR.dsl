/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20200925 (64-bit version)
 * Copyright (c) 2000 - 2020 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of SSDT-NVPWR.aml, Sat Nov 14 00:00:01 2026
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x000000D2 (210)
 *     Revision         0x02
 *     Checksum         0xFB
 *     OEM ID           "LKTSI"
 *     OEM Table ID     "NVPWR"
 *     OEM Revision     0x00001000 (4096)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20200925 (538970405)
 */
DefinitionBlock ("", "SSDT", 2, "LKTSI", "NVPWR", 0x00001000)
{
    External (_SB_.PC00.PEG0, DeviceObj)
    External (_SB_.PC00.PEG0.PCRP, PowerResObj)
    External (_SB_.PC00.PEG0.PCRP._OFF, MethodObj)    // 0 Arguments
    External (_SB_.PC00.PEG0.PCRP._ON_, MethodObj)    // 0 Arguments

    Scope (\_SB.PC00.PEG0)
    {
        Method (XPOF, 0, Serialized)
        {
            \_SB.PC00.PEG0.PCRP._OFF ()
        }

        Method (XPON, 0, Serialized)
        {
            \_SB.PC00.PEG0.PCRP._ON ()
        }
    }
}

