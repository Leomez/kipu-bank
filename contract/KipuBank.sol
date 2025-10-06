// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title KipuBank - Banco para depósitos nativos de ETH con límite por retiro y límite global
/// @author Leonardo Meza
/// @notice Permite depósitos en ETH por usuario y retiros hasta un límite por transacción.
/// @dev Implementa buenas prácticas: errores personalizados, checks-effects-interactions, modifier nonReentrant, NatSpec.
contract KipuBank {
    /* ---------------------------------------------     EVENTOS    --------------------------------------------- */

    /// @notice Se emite cuando un usuario deposita ETH en su cuenta.
    /// @param who Dirección de la depositante.
    /// @param amount Cantidad de ETH depositado (en wei).
    /// @param balanceAfter Nuevo saldo de la cuenta del usuario luego del depósito.
    event Deposit(address indexed who, uint256 amount, uint256 balanceAfter);

    /// @notice Se emite cuando un usuario retira ETH de su cuenta.
    /// @param who Direccion de quien retira.
    /// @param amount Cantidad de ETH que retira (en wei).
    /// @param balanceAfter Nuevo saldo de la cuenta del usuario luego del retiro.
    event Withdraw(address indexed who, uint256 amount, uint256 balanceAfter);

    /* -----------------------------------------------   ERRORES   ----------------------------------------------- */

    /// @notice Se excedió el límite total del banco al depositar.
    /// @param attemptedTotal El balance total que el banco tendría después del intento de depósito.
    error ErrBankCapExceeded(uint256 attemptedTotal);

    /// @notice El usuario no tiene suficiente saldo para realizar el retiro solicitado.
    /// @param available Saldo disponible actual.
    /// @param requested Monto solicitado para retirar.
    error ErrInsufficientBalance(uint256 available, uint256 requested);
    
    /// @notice El monto solicitado para retirar excede el límite permitido por transacción.
    /// @param requested Monto solicitado para retirar.
    /// @param limit Límite máximo por retiro (inmutable).
    error ErrWithdrawTooLarge(uint256 requested, uint256 limit);

    /// @notice Se recibió un valor cero cuando se esperaba un monto distinto de cero.
    error ErrZeroAmount();
    
    /// @notice Se detectó una llamada reentrante.
    error ErrReentrant();

    /// @notice Falló la transferencia de ETH.
    /// @param to Dirección del destinatario.
    /// @param amount Monto que se intentó transferir.
    error ErrSendFailed(address to, uint256 amount);

    /* ---------------------------------       VARIABLES INMUTABLE / CONSTANTES / DE ESTADO    ------------------------------------ */

    /// @notice Monto máximo permitido por transacción de retiro (en wei). Inmutable después del despliegue.
    uint256 public immutable WITHDRAW_LIMIT;

    /// @notice Límite global máximo de ETH que el banco puede mantener entre todos los usuarios (en wei). Inmutable después del despliegue.
    uint256 public immutable BANK_CAP;

    /// @notice Dirección que desplegó el contrato (propietario). Inmutable.
    address public immutable OWNER;

    /// @notice Total de ETH actualmente mantenido por el banco (suma de todos los saldos de las cuentas). Se mantiene sincronizado.
    uint256 public totalBankBalance;
    
    /// @notice Mapeo de la dirección del usuario a su saldo (en wei).
    mapping(address => uint256) private balances;

    /// @notice Mapeo para registrar la cantidad de depósitos realizados por usuario.
    mapping(address => uint256) private depositCount;

    /// @notice Mapeo para registrar la cantidad de retiros realizados por usuario.
    mapping(address => uint256) private withdrawCount;

    /// @notice Contadores globales de depósitos y retiros.
    uint256 public totalDeposits;
    uint256 public totalWithdraws;

    /* -----------------------------------------      PROTECCION CONTRA REENTRANCIA     ----------------------------------------- */

    uint8 private constant _NOT_ENTERED = 1;
    uint8 private constant _ENTERED = 2;
    uint8 private _status;

    /* ---------------------------------------------     MODIFICADORES    -------------------------------------------- */

    /// @notice Evita llamadas reentrantes.
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ErrReentrant();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    /// @notice Solo el propietario (deployer) puede ejecutar esta función (útil para tareas administrativas futuras).
    modifier onlyOwner() {
        require(msg.sender == OWNER, "only owner");
        _;
    }

    /* ------------------------------------------     CONSTRUCTOR    ------------------------------------------- */

    /// @notice Despliega KipuBank con un límite global y un límite máximo por retiro.
    /// @param bankCap_ Límite global máximo de ETH que el banco podrá mantener (en wei).
    /// @param withdrawLimit_ Límite máximo que un usuario puede retirar por transacción (en wei).
    constructor(uint256 bankCap_, uint256 withdrawLimit_) {
        require(bankCap_ > 0, "bankCap>0");
        require(withdrawLimit_ > 0, "withdrawLimit>0");

        BANK_CAP = bankCap_;
        WITHDRAW_LIMIT = withdrawLimit_;
        OWNER = msg.sender;

        _status = _NOT_ENTERED;
    }

    /* ---------------------------------       FUNCIONES EXTERNAS / PÚBLICAS    ------------------------------------ */

    /// @notice Deposita ETH nativo en la bóveda del usuario que llama.
    /// @dev Sigue el patrón checks-effects-interactions. Emite el evento `Deposit`.
    /// @return newBalance Nuevo saldo de la bóveda después del depósito.
    function deposit() external payable nonReentrant returns (uint256 newBalance) {
        if (msg.value == 0) revert ErrZeroAmount();

        // Verifica el límite global del banco
        uint256 newTotal = totalBankBalance + msg.value;
        if (newTotal > BANK_CAP) revert ErrBankCapExceeded(newTotal);

        // Efectos
        balances[msg.sender] += msg.value;
        totalBankBalance = newTotal;

        // Actualiza contadores
        depositCount[msg.sender] += 1;
        totalDeposits += 1;

        // Sin interacciones externas. Solo cambios de estado. Emite evento.
        newBalance = balances[msg.sender];
        emit Deposit(msg.sender, msg.value, newBalance);
    }

    /// @notice Permite retirar hasta `WITHDRAW_LIMIT` desde la bóveda del usuario hacia su dirección.
    /// @param amount Monto (en wei) a retirar.
    /// @dev Usa el patrón checks-effects-interactions y una función privada segura para transferencias.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ErrZeroAmount();
        if (amount > WITHDRAW_LIMIT) revert ErrWithdrawTooLarge(amount, WITHDRAW_LIMIT);

        uint256 userBalance = balances[msg.sender];
        if (amount > userBalance) revert ErrInsufficientBalance(userBalance, amount);

        // Efectos
        balances[msg.sender] = userBalance - amount;
        totalBankBalance -= amount;
        withdrawCount[msg.sender] += 1;
        totalWithdraws += 1;

        // Interacción: transfiere ETH de forma segura usando call y verifica el resultado
        _safeSend(payable(msg.sender), amount);

        emit Withdraw(msg.sender, amount, balances[msg.sender]);
    }

    /// @notice Devuelve el saldo de la bóveda de una dirección específica.
    /// @param who Dirección a consultar.
    /// @return balance Saldo actual en wei.
    function getBalance(address who) external view returns (uint256 balance) {
        return balances[who];
    }

    /// @notice Devuelve la cantidad de depósitos realizados por una dirección.
    /// @param who Dirección a consultar.
    function getDepositCount(address who) external view returns (uint256) {
        return depositCount[who];
    }

    /// @notice Devuelve la cantidad de retiros realizados por una dirección.
    /// @param who Dirección a consultar.
    function getWithdrawCount(address who) external view returns (uint256) {
        return withdrawCount[who];
    }

    /// @notice Función `receive` que permite depósitos directos enviando ETH sin datos.
    /// @dev Replica la lógica de `deposit()` para manejar transferencias directas y emitir eventos correctamente.
    receive() external payable {
        if (msg.value == 0) revert ErrZeroAmount();

        uint256 newTotal = totalBankBalance + msg.value;
        if (newTotal > BANK_CAP) revert ErrBankCapExceeded(newTotal);

        balances[msg.sender] += msg.value;
        totalBankBalance = newTotal;

        depositCount[msg.sender] += 1;
        totalDeposits += 1;

        emit Deposit(msg.sender, msg.value, balances[msg.sender]);
    }

    /// @notice Rechaza cualquier llamada con datos no válidos.
    fallback() external payable {
        revert();
    }

    /* ------------------------------------       FUNCIONES PRIVADAS / INTERNAS    --------------------------------------- */

    /// @notice Envía ETH de forma segura usando el patrón `call`. Revierte con `ErrSendFailed` en caso de error.
    /// @param to Dirección del destinatario.
    /// @param amount Monto en wei a enviar.
    function _safeSend(address payable to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert ErrSendFailed(to, amount);
    }

    /* ---------------------------------       FUNCIONES ADMIN / VISTA (opcionales)    ------------------------------------ */

    /// @notice Función de solo lectura (soloOwner) que devuelve un resumen del contrato.
    /// @return bankCap Límite global del banco en wei.
    /// @return withdrawLimit Límite por retiro en wei.
    /// @return bankBalance Balance total actual del banco en wei.
    function summary()
        external
        view
        returns (uint256 bankCap, uint256 withdrawLimit, uint256 bankBalance)
    {
        return (BANK_CAP, WITHDRAW_LIMIT, totalBankBalance);
    }
}