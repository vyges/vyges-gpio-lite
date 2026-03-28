# vyges-gpio-lite

Lightweight GPIO peripheral with a native TL-UL (TileLink Uncached Lightweight)
slave interface. Designed as a drop-in peripheral for OpenTitan-based and
TileLink SoCs without requiring RACL, alert, or lifecycle dependencies.

## Features

- Configurable pin count (1--32, default 32)
- Per-pin direction control (input / output)
- Per-pin interrupt support: rising edge, falling edge, or both
- 2-FF metastability synchronizer on all inputs
- Atomic bit-set / bit-clear registers for output data
- Write-1-to-clear interrupt status
- Single-cycle TL-UL response (always ready)

## Register Map

| Offset | Name       | Access | Description                             |
|--------|------------|--------|-----------------------------------------|
| 0x00   | DATA_OUT   | RW     | Output data register                    |
| 0x04   | DATA_IN    | RO     | Input data (2-FF synchronized)          |
| 0x08   | DIR        | RW     | Direction: 1 = output, 0 = input        |
| 0x0C   | INTR_EN    | RW     | Interrupt enable per pin                |
| 0x10   | INTR_RISE  | RW     | Rising-edge interrupt enable per pin    |
| 0x14   | INTR_FALL  | RW     | Falling-edge interrupt enable per pin   |
| 0x18   | INTR_ST    | W1C    | Interrupt status (write-1-to-clear)     |
| 0x1C   | OUT_SET    | WO     | Set bits in DATA_OUT (write 1 to set)   |
| 0x20   | OUT_CLR    | WO     | Clear bits in DATA_OUT (write 1 to clr) |

## Parameters

| Parameter | Type         | Default | Description            |
|-----------|--------------|---------|------------------------|
| NUM_PINS  | int unsigned | 32      | Number of GPIO pins    |

## SoC Integration Example (soc-spec.yaml)

```yaml
peripherals:
  - name: gpio0
    ip: vyges-gpio-lite
    base_addr: 0x4000_0000
    parameters:
      NUM_PINS: 16
    connections:
      gpio_i: pad_gpio_i[15:0]
      gpio_o: pad_gpio_o[15:0]
      gpio_oe_o: pad_gpio_oe[15:0]
      intr_gpio_o: intr[3]
```

## Dependencies

- `opentitan-tlul` -- provides `tlul_pkg` (TL-UL struct types and opcodes).

## License

Apache-2.0. See [LICENSE](LICENSE).
