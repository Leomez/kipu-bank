**KipuBank** es un contrato inteligente de práctica que implementa bóvedas personales para depositar ETH nativo. Permite depósitos y retiros con las siguientes reglas:

- Cada usuario tiene una **bóveda** (balance individual).
- Existe un **límite global** (BANK_CAP) —el máximo total de ETH que el banco puede contener— fijado en deploy.
- Existe un **límite por retiro** (WITHDRAW_LIMIT) —máximo que se puede retirar por transacción— fijado en deploy (inmutable).
- Se usan **errores personalizados**, **events**, y **patrones de seguridad** (checks-effects-interactions, reentrancy guard).


---

## Estructura del repo
kipu-bank/
├─ contracts/
│ └─ KipuBank.sol
└─ README.md

---

## Archivo principal

`contracts/KipuBank.sol`

- Variables inmutables: `BANK_CAP`, `WITHDRAW_LIMIT`, `OWNER`
- Variables de almacenamiento: `totalBankBalance`, `balances`, contadores
- Mapping: `mapping(address => uint256) balances, depositCount, withdrawCount`
- Eventos: `Deposit`, `Withdraw`
- Errores personalizados: `ErrBankCapExceeded`, `ErrInsufficientBalance`, `ErrWithdrawTooLarge`, `ErrZeroAmount`, `ErrReentrant`, `ErrSendFailed`
- Constructor: recibe `bankCap_` y `withdrawLimit_`
- Modificador: `nonReentrant` (reentrancy guard)
- Funciones:
  - `deposit() external payable`
  - `withdraw(uint256 amount) external`
  - `getBalance(address) external view`
  - `receive()` (acepta ETH directos)
  - `_safeSend(address payable, uint256)` private

---

## Cómo desplegar en Remix (guía paso a paso)

> Recomendado: usa la red **Sepolia** o la testnet que elijas. Asegurate de tener MetaMask configurado.

1. Abrí [Remix IDE](https://remix.ethereum.org).
2. Creá el archivo `contracts/KipuBank.sol` y pega el contenido del contrato.
3. Compilá:
   - Panel "Solidity Compiler"
   - Versión: `0.8.20` (o `^0.8.20`) — selecciona una versión compatible.
   - Presiona "Compile".
4. Conecta MetaMask:
   - En "Deploy & Run Transactions", en "Environment" selecciona "Injected Provider - MetaMask".
   - Cambia MetaMask a la testnet (ej. Sepolia) y obtené ETH de faucet si necesitas.
5. Despliegue:
   - En `Deploy` configura los parámetros del constructor:
     - `bankCap_`: cantidad en wei (p. ej. `1000000000000000000` para 1 ETH).
     - `withdrawLimit_`: límite por retiro en wei (p. ej. `500000000000000000` para 0.5 ETH).
   - Hacé click en `Deploy`.
   - Confirmá la transacción en MetaMask.
6. Interactuar:
   - `deposit()` — ingresá ethers en el campo "value" (en ETH), luego pulsa `deposit`.
   - `getBalance(address)` — consultá el balance de cualquier dirección.
   - `withdraw(amount)` — especificá la cantidad en wei y ejecutá para retirar.
   - `getDepositCount(address)` → cantidad de depósitos del usuario.
   - `getWithdrawCount(address)` → cantidad de retiros del usuario.
   - `summary()` → muestra los valores globales (BANK_CAP, WITHDRAW_LIMIT, totalBankBalance).

---
