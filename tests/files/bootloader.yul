object "Bootloader" {
    code {
    }
    object "Bootloader_deployed" {
        code {
            /// @notice the address that will be the beneficiary of all the fees
            let OPERATOR_ADDRESS := mload(0)
            /// @notice the price for the pubdata for L2 transactions
            let PUBDATA_PRICE_IN_BLOCK := mload(32)

            // Initializing block params
            {
                /// @notice The hash of the previous block
                let PREV_BLOCK_HASH := mload(64)
                /// @notice The timestamp of the block being processed
                let NEW_BLOCK_TIMESTAMP := mload(96)
                /// @notice The number of the new block being processed.
                /// While this number is deterministic for each block, we
                /// still provide it here to ensure consistency between the state
                /// of the VM and the state of the operator.
                let NEW_BLOCK_NUMBER := mload(128)

                <!-- @if BOOTLOADER_TYPE=='proved_block' -->

                setNewBlock(PREV_BLOCK_HASH, NEW_BLOCK_TIMESTAMP, NEW_BLOCK_NUMBER)

                <!-- @endif -->

                <!-- @if BOOTLOADER_TYPE=='playground_block' -->

                let SHOULD_SET_NEW_BLOCK := mload(160)

                // The state keeper version (i.e. the one that is used for actually processing the transactions)
                // is required to call the `setNewBlock` method (it is enforced by the L1 contract).
                switch SHOULD_SET_NEW_BLOCK 
                case 0 {    
                    unsafeOverrideBlock(NEW_BLOCK_TIMESTAMP, NEW_BLOCK_NUMBER)
                }
                default {
                    setNewBlock(PREV_BLOCK_HASH, NEW_BLOCK_TIMESTAMP, NEW_BLOCK_NUMBER)
                }

                <!-- @endif -->
            }
            
            /// @dev The maximum number of transactions per L1 batch.
            function MAX_TXS_IN_BLOCK() -> ret {
                ret := 256
            }

            /// @dev The slot from which the debug slots start
            function DEBUG_SLOTS_BEGIN_SLOT() -> ret {
                ret := 6
            }

            /// @dev The first 32 slots are reserved for event emitting for the 
            /// debugging purposes
            function DEBUG_SLOTS() -> ret {
                ret := 32
            }

            /// @dev Slots reserved for saving the paymaster context
            /// @dev The paymasters are allowed to consume at most 
            /// 32 slots (1024 bytes) for their context.
            /// The 33 slots are required since the first one stores the length of the calldata.
            function PAYMASTER_CONTEXT_SLOTS() -> ret {
                ret := 33
            }
        
            /// @dev Bytes reserved for saving the paymaster context
            function PAYMASTER_CONTEXT_BYTES() -> ret {
                ret := mul(PAYMASTER_CONTEXT_SLOTS(), 32)
            }

            /// @dev Slot from which the paymaster context starts
            function PAYMASTER_CONTEXT_BEGIN_SLOT() -> ret {
                ret := add(DEBUG_SLOTS_BEGIN_SLOT(), DEBUG_SLOTS())
            }

            /// @dev The byte from which the paymaster context starts
            function PAYMASTER_CONTEXT_BEGIN_BYTE() -> ret {
                ret := mul(PAYMASTER_CONTEXT_BEGIN_SLOT(), 32)
            }

            /// @dev Each tx must have at least this amount of unused bytes before them to be able to 
            /// encode the postOp operation correctly.
            function MAX_POSTOP_SLOTS() -> ret {
                // Before the actual transaction encoding, the postOp contains 4 slots:
                // context offset, transaction offset, transaction result, maxRefundedErgs
                ret := add(PAYMASTER_CONTEXT_SLOTS(), 7)
            }

            /// @dev Slots needed to store the canonical and signed hash for the current L2 transaction.
            function CURRENT_L2_TX_HASHES_RESERVED_SLOTS() -> ret {
                ret := 2
            }

            /// @dev Slot from which storing of the current canonical and signed hashes begins
            function CURRENT_L2_TX_HASHES_BEGIN_SLOT() -> ret {
                ret := add(PAYMASTER_CONTEXT_BEGIN_SLOT(), PAYMASTER_CONTEXT_SLOTS())
            }

            /// @dev The byte from which storing of the current canonical and signed hashes begins
            function CURRENT_L2_TX_HASHES_BEGIN_BYTE() -> ret {
                ret := mul(CURRENT_L2_TX_HASHES_BEGIN_SLOT(), 32)
            }

            /// @dev The maximum number of new factory deps that are allowed in a transaction
            function MAX_NEW_FACTORY_DEPS() -> ret {
                ret := 32
            }

            /// @dev Besides the factory deps themselves, we also need another 4 slots for: 
            /// selector, marker of whether the user should pay for the pubdata,
            /// the offset for the encoding of the array as well as the length of the array.
            function NEW_FACTORY_DEPS_RESERVED_SLOTS() -> ret {
                ret := add(MAX_NEW_FACTORY_DEPS(), 4)
            }

            /// @dev The slot starting from which the factory dependencies are stored
            function NEW_FACTORY_DEPS_BEGIN_SLOT() -> ret {
                ret := add(CURRENT_L2_TX_HASHES_BEGIN_SLOT(), CURRENT_L2_TX_HASHES_RESERVED_SLOTS())
            }

            /// @dev The byte starting from which the factory dependencies are stored
            function NEW_FACTORY_DEPS_BEGIN_BYTE() -> ret {
                ret := mul(NEW_FACTORY_DEPS_BEGIN_SLOT(), 32)
            }
            
            /// @dev Total number of slots reserved for auxilary and block parameters' data
            function RESERVED_FREE_SLOTS() -> ret {
                ret := add(NEW_FACTORY_DEPS_BEGIN_SLOT(), NEW_FACTORY_DEPS_RESERVED_SLOTS())
            }

            /// @dev The byte from which the bootloader transactions' descriptions begin
            function TX_DESCRIPTION_START_PTR() -> ret {
                ret := mul(RESERVED_FREE_SLOTS(), 32)
            }

            // Each tx description has the following structure
            // 
            // struct BootloaderTxDescription {
            //     uint256 txMeta;
            //     uint256 txDataOffset;
            // }
            //
            // `txMeta` contains flags to manipulate the transaction execution flow.
            // For playground blocks:
            //      It can have the following information (0 byte is LSB and 31 byte is MSB):
            //      0 byte: `execute`, bool. Denotes whether transaction should be executed by the bootloader.
            //      31 byte: server-side tx execution mode
            // For proved blocks:
            //      It can simply denotes whether to execute the transaction (0 to stop executing the block, 1 to continue) 
            //
            // Each such encoded struct consumes 2 words
            let TX_DESCRIPTION_SIZE := mul(32, 2)

            /// @dev The byte right after the basic description of bootloader transactions
            let TXS_IN_BLOCK_LAST_PTR := add(TX_DESCRIPTION_START_PTR(), mul(MAX_TXS_IN_BLOCK(), TX_DESCRIPTION_SIZE))


            /// @dev The memory page consists of 2^16 VM words.
            /// Each execution result is a single boolean, but 
            /// for the sake of simplicity we will spend 32 bytes on each
            /// of those for now. 
            function MAX_MEM_SIZE() -> ret {
                ret := 0x1000000 // 2^24 bytes
            }

            /// @dev The byte from which the pointers on the result of transactions are stored
            function RESULT_START_PTR() -> ret {
                ret := sub(MAX_MEM_SIZE(), mul(MAX_TXS_IN_BLOCK(), 32))
            }

            /// @dev The pointer writing to which invokes the VM hooks
            function VM_HOOK_PTR() -> ret {
                ret := sub(RESULT_START_PTR(), 32)
            }

            /// @dev The maximum number the VM hooks may accept
            function VM_HOOK_PARAMS() -> ret {
                ret := 2
            }

            /// @dev The offset starting from which the parameters for VM hooks are located
            function VM_HOOK_PARAMS_OFFSET() -> ret {
                ret := sub(VM_HOOK_PTR(), mul(VM_HOOK_PARAMS(), 32))
            }

            function LAST_FREE_SLOT() -> ret {
                // The slot right before the vm hooks is the last slot that
                // can be used for transaction's descriptions
                ret := sub(VM_HOOK_PARAMS_OFFSET(), 32)
            }

            /// @dev The formal address of the bootloader
            function BOOTLOADER_FORMAL_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008001
            }

            function ACCOUNT_CODE_STORAGE_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008002
            }

            function KNOWN_CODES_CONTRACT_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008004
            }

            function CONTRACT_DEPLOYER_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008006
            }

            function MSG_VALUE_SIMULATOR_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008009
            }

            function ETH_L2_TOKEN_ADDR() -> ret {
                ret := 0x000000000000000000000000000000000000800a
            }

            function SYSTEM_CONTEXT_ADDR() -> ret {
                ret := 0x000000000000000000000000000000000000800b
            }

            function NONCE_HOLDER_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008003
            }

            function BOOTLOADER_UTILITIES() -> ret {
                ret := 0x000000000000000000000000000000000000800c
            }

            /// @dev The bit used to inform MsgValueSimulator that a call
            /// should be a system one.  
            function IS_SYSTEM_CALL_MSG_VALUE_BIT() -> ret {
                ret := shl(128, 1)
            }

            /// @dev It is required that at least some amount of ergs are spare after the verification step.
            /// Currently the number is rather arbitrary, but in general it should cover the expenses of 
            /// starting the execute step of the transaction.
            function MIN_LEFT_AFTER_VERIFY() -> ret {
                ret := 20
            }

            // This address will be used as dummy address for all the other system contracts
            // The exact addresses of the system contracts are yet to be known and are not relevant. 
            // address constant dummyAddress = address(0x0);
            // address constant BOOTLOADER_ADDRESS = address(0x1);

            // Input is layed out the following way:
            // Starting from the memory slot NEW_CODE_HASHES_START_PTR there are `MAX_NEW_CODE_HASHES` 256-bit code 
            // hashes. Then there are `MAX_TXS_IN_BLOCK` basic transaction data pointers.

            // Now, we iterate over all transactions, processing each of them
            // one by one.
            // Here, the `resultPtr` is the pointer to the memory slot, where we will write
            // `true` or `false` based on whether the tx execution was successful,

            // The position at which the tx offset of the transaction should be placed
            let currentExpectedTxOffset := add(TXS_IN_BLOCK_LAST_PTR, mul(MAX_POSTOP_SLOTS(), 32))

            let ptr := TX_DESCRIPTION_START_PTR()

            // Iterating through transaction descriptions
            for { let resultPtr := RESULT_START_PTR() } lt(ptr, TXS_IN_BLOCK_LAST_PTR) { 
                ptr := add(ptr, TX_DESCRIPTION_SIZE)
                resultPtr := add(resultPtr, 32)
            } {
                let execute := mload(ptr)

                debugLog("ptr", ptr)
                debugLog("execute", execute)
                
                if iszero(execute) {
                    // We expect that all transactions that are executed
                    // are continuous in the array.
                    break
                }

                let txDataOffset := mload(add(ptr, 32))

                // We strongly enforce the positions of transactions
                if iszero(eq(currentExpectedTxOffset, txDataOffset)) {
                    debugLog("currentExpectedTxOffset", currentExpectedTxOffset)
                    debugLog("txDataOffset", txDataOffset)

                    assertionError("Tx data offset is not in correct place")
                }

                currentExpectedTxOffset := validateAbiEncoding(add(0x20, txDataOffset))
                // Checking whether the last slot of the transaction's description
                // does not go out of bounds.
                if gt(sub(currentExpectedTxOffset, 32), LAST_FREE_SLOT()) {
                    debugLog("currentExpectedTxOffset", currentExpectedTxOffset)
                    debugLog("LAST_FREE_SLOT", LAST_FREE_SLOT())

                    assertionError("currentExpectedTxOffset too high")
                }
                validateTypedTxStructure(add(0x20, txDataOffset))
    
                <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                {
                    debugLog("ethCall", 0)
                    processTx(txDataOffset, resultPtr, 0, PUBDATA_PRICE_IN_BLOCK)
                }
                <!-- @endif -->
                <!-- @if BOOTLOADER_TYPE=='playground_block' -->
                {
                    let txMeta := mload(ptr)
                    let processFlags := getWordByte(txMeta, 31)
                    debugLog("flags", processFlags)


                    // `processFlags` argument denotes which parts of execution should be done:
                    //  Possible values:
                    //     0x00: validate & execute (normal mode)
                    //     0x02: perform ethCall (i.e. use mimicCall to simulate the call)

                    let isETHCall := eq(processFlags, 0x02)
                    debugLog("ethCall", isETHCall)
                    processTx(txDataOffset, resultPtr, isETHCall, PUBDATA_PRICE_IN_BLOCK)
                }
                <!-- @endif -->
                // Signal to the vm that the transaction execution is complete
                setHook(VM_HOOK_TX_HAS_ENDED())
                // Increment tx index within the system.
                considerNewTx()
            }

            // Reseting tx.origin and ergsPrice (gasPrice) to 0, so we don't pay for
            // publishing them on-chain.
            setTxOrigin(0)
            setErgsPrice(0)

            // Transfering all the ETH received in the block to the operator
            let rewardingOperatorSuccess := call(
                gas(),
                OPERATOR_ADDRESS,
                selfbalance(),
                0,
                0,
                0,
                0
            )

            if iszero(rewardingOperatorSuccess) {
                // If failed to send ETH to the operator, panic
                revertWithReason(
                    FAILED_TO_SEND_FEES_TO_THE_OPERATOR(),
                    1
                )
            }
            
            /// @dev Converts length to bytes to the number of full words needed for it
            /// Basically this is ceil(len/32) 
            function lengthToWords(len) -> ret {
                let p := div(len, 32)
                ret := add(mul(p, 32), 32)

                if iszero(mod(len, 32)) {
                    ret := sub(ret, 32)
                }
            }

            /// @dev Function responsible for processing the transaction
            /// @param txDataOffset The offset to the ABI-encoding of the structure
            /// @param resultPtr The pointer at which the result of the transaction's execution should be stored
            /// @param isETHCall Whether the call is an ethCall. 
            /// On proved block this value should always be zero
            /// @param pubdataPriceInBlock The price (in ergs) for publishing a single byte of pubdata.
            /// This price is used only for L2 transactions as L1 transactions receive this parameter from L1.  
            function processTx(
                txDataOffset, 
                resultPtr, 
                isETHCall,
                pubdataPriceInBlock
            ) {
                // The first word stored at the `txDataOffset` should be formal 0x20
                // for the ABI encoding of the Transaction struct. So we ignore it when 
                // doing most of the operations with the transaction.
                let innerTxDataOffset := add(txDataOffset, 32)
                let txType := getTxType(innerTxDataOffset)
                let FROM_L1_TX_TYPE := 255
                let isL1Tx := eq(txType, FROM_L1_TX_TYPE)

                // By default we assume that the transaction has failed.
                mstore(resultPtr, 0)

                switch isL1Tx 
                    case 1 { processL1Tx(txDataOffset, resultPtr) }
                    default {
                        let userProvidedPubdataPrice := getErgsPerPubdataByteLimit(innerTxDataOffset)
                        debugLog("pubdataPriceInBlock:", pubdataPriceInBlock)
                        debugLog("userProvidedPubdataPrice:", userProvidedPubdataPrice)
                        // The user did not agree to such a pubdata price, we should revert.
                        if gt(pubdataPriceInBlock, userProvidedPubdataPrice) {  
                            revertWithReason(UNACCEPTABLE_PUBDATA_PRICE_ERR_CODE(), 0)
                        }

                        setPricePerPubdataByte(pubdataPriceInBlock)

                        <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                        processL2Tx(txDataOffset, resultPtr)
                        <!-- @endif -->

                        <!-- @if BOOTLOADER_TYPE=='playground_block' -->
                        switch isETHCall 
                            case 1 {
                                let ergsLimit := getErgsLimit(innerTxDataOffset)
                                let nearCallAbi := getNearCallABI(ergsLimit)
                                checkEnoughGas(ergsLimit)
                                ZKSYNC_NEAR_CALL_ethCall(
                                    nearCallAbi,
                                    txDataOffset,
                                    resultPtr
                                )
                            }
                            default { 
                                processL2Tx(txDataOffset, resultPtr)
                            }
                        <!-- @endif -->
                    }
            }

            /// @dev Calculates the canonical hash of the L1->L2 transaction that will be
            /// sent to L1 as a message to the L1 contract that a certain operation has been processed.
            function getCanonicalL1TxHash(txDataOffset) -> ret {
                // Putting the correct value at the `txDataOffset` just in case, since 
                // the correctness of this value is not part of the system invariants.
                mstore(txDataOffset, 0x20)

                let innerTxDataOffset := add(txDataOffset, 32)
                let dataLength := add(32, getDataLength(innerTxDataOffset))

                debugLog("HASH_OFFSET", innerTxDataOffset)
                debugLog("DATA_LENGTH", dataLength)

                ret := keccak256(txDataOffset, dataLength)
            }

            /// @dev The purpose of this function is to make sure that the operator
            /// gets paid for the transaction. Note, that the beneficiary of the payment is 
            /// bootloader.
            /// The operator will be paid at the end of the block.
            function ensurePayment(txDataOffset, ergsPrice) {
                // Skipping the first 0x20 byte in the encoding of the transaction.
                let innerTxDataOffset := add(txDataOffset, 32)
                let from := getFrom(innerTxDataOffset)
                let requiredETH := mul(getErgsLimit(innerTxDataOffset), ergsPrice)

                let bootloaderBalanceETH := balance(BOOTLOADER_FORMAL_ADDR())
                let paymaster := getPaymaster(innerTxDataOffset)

                switch paymaster
                case 0 {
                    // There is no paymaster, the user should pay for the execution.
                    // Calling for the `payForTransaction` method of the account.
                    setHook(VM_HOOK_ACCOUNT_VALIDATION_ENTERED())
                    let res := accountPayForTx(from, txDataOffset)
                    setHook(VM_HOOK_NO_VALIDATION_ENTERED())


                    if iszero(res) {
                        revertWithReason(
                            PAY_FOR_TX_FAILED_ERR_CODE(),
                            1
                        )
                    }
                }   
                default {
                    // There is some paymaster present. 

                    // Firsly, the `prepareForPaymaster` method of the user's account is called.
                    setHook(VM_HOOK_ACCOUNT_VALIDATION_ENTERED())
                    let userPrePaymasterResult := accountPrePaymaster(from, txDataOffset)
                    setHook(VM_HOOK_NO_VALIDATION_ENTERED())

                    if iszero(userPrePaymasterResult) {
                        revertWithReason(
                            PRE_PAYMASTER_PREPARATION_FAILED_ERR_CODE(),
                            1
                        )
                    }

                    // Then, the paymaster is called. The paymaster should pay us in this method.
                    setHook(VM_HOOK_PAYMASTER_VALIDATION_ENTERED())
                    let paymasterPaymentSuccess := validateAndPayForPaymasterTransaction(paymaster, txDataOffset)
                    if iszero(paymasterPaymentSuccess) {
                        revertWithReason(
                            PAYMASTER_VALIDATION_FAILED_ERR_CODE(),
                            1
                        )
                    }
                    storePaymasterContext()
                    setHook(VM_HOOK_NO_VALIDATION_ENTERED())
                }

                let bootloaderReceivedFunds := sub(balance(BOOTLOADER_FORMAL_ADDR()), bootloaderBalanceETH)

                // If the amount of funds provided to the bootloader is less than the minimal required one
                // then this transaction should be rejected.                
                if lt(bootloaderReceivedFunds, requiredETH)  {
                    revertWithReason(
                        FAILED_TO_CHARGE_FEE_ERR_CODE(),
                        0
                    )
                }
            }

            /// @dev Saves the paymaster context.
            /// @dev IMPORTANT: this method should be called right after 
            /// the validateAndPayForPaymasterTransaction method to keep the `returndata` from that transaction
            function storePaymasterContext()    {
                // The paymaster validation step should return context of type "bytes context"
                // This means that the returndata is encoded the following way:
                // 0x20 || context_len || context_bytes...
                let returnlen := returndatasize()
                // The minimal allowed returndatasize is 64: 0x20 || 0x00
                if lt(returnlen, 64) {
                    revertWithReason(
                        PAYMASTER_RETURNED_INVALID_CONTEXT(),
                        0
                    )
                }

                // We don't care about the first 32 bytes as they are formal and always equal to 0x20
                let effectiveReturnLen := sub(returnlen, 32)

                // The returned context's size should not exceed the maximum length
                if gt(effectiveReturnLen, PAYMASTER_CONTEXT_BYTES()) {
                    revertWithReason(
                        PAYMASTER_RETURNED_CONTEXT_IS_TOO_LONG(),
                        0
                    )
                }

                returndatacopy(PAYMASTER_CONTEXT_BEGIN_BYTE(), 32, effectiveReturnLen)
                
                // The last sanity check: the first word contains the actual length of the context and so 
                // it should not be greater than effectiveReturnLen - 32
                let lenFromSlot := mload(PAYMASTER_CONTEXT_BEGIN_BYTE())
                if gt(lenFromSlot, sub(effectiveReturnLen, 32)) {
                    revertWithReason(
                        PAYMASTER_RETURNED_INVALID_CONTEXT(),
                        0
                    )
                }
            }

            /// @dev The function responsible for processing L1->L2 transactions.
            /// @param txDataOffset The offset to the transaction's information
            /// @param resultPtr The pointer at which the result of the execution of this transaction
            /// should be stored.
            function processL1Tx(
                txDataOffset,
                resultPtr
            ) {
                // Skipping the first formal 0x20 byte
                let innerTxDataOffset := add(txDataOffset, 32) 
                let ergsBeforePreparation := gas()

                let ergsLimit := getErgsLimit(innerTxDataOffset)
                let ergsPerPubdataByte := getErgsPerPubdataByteLimit(innerTxDataOffset)

                debugLog("ergsLimit", ergsLimit)
                debugLog("ergsBeforePreparation", ergsBeforePreparation)
                // For L1->L2 transactions we use the ergsPerPubdataByte set on the L1
                setPricePerPubdataByte(ergsPerPubdataByte)
                debugLog( "ergsPerPubdataByte", ergsPerPubdataByte)

                // Even though the smart contracts on L1 should make sure that the L1->L2 provide enough ergs to generate the hash
                // we should still be able to do it even if this protection layer fails.
                let canonicalL1TxHash := getCanonicalL1TxHash(txDataOffset)
                debugLog("l1 hash", canonicalL1TxHash)

                markFactoryDepsForTx(innerTxDataOffset, true)

                debugLog( "completed mark factory dps", ergsPerPubdataByte)

                let ergsUsedOnPreparation := sub(ergsBeforePreparation, gas())
                debugLog("ergsUsedOnPreparation", ergsUsedOnPreparation)

                // Whether the user still has the ergs needed to process the transaction
                let canExecute := gt(ergsLimit, add(ergsUsedOnPreparation, MIN_LEFT_AFTER_VERIFY()))

                debugLog("canExecute", canExecute)

                let success := 0
                if canExecute {
                    let ergsForExecution := sub(ergsLimit, ergsUsedOnPreparation)
                    debugLog("ergsForExecution", ergsForExecution)

                    let callAbi := getNearCallABI(ergsForExecution)
                    debugLog("callAbi", callAbi)

                    checkEnoughGas(ergsForExecution)
                    success := ZKSYNC_NEAR_CALL_executeL1Tx(
                        callAbi,
                        txDataOffset
                    )
                }
                // TODO: make user pay for sending back the L1 message
                mstore(resultPtr, success)
                
                debugLog("Send message to L1", success)
                
                // Sending the L2->L1 to notify the L1 contracts that the priority 
                // operation has been processed.
                sendToL1(true, canonicalL1TxHash, success)
            }

            /// @dev Returns the ergs price that should be used by the transaction 
            /// based on the EIP1559's maxFeePerErg and maxPriorityFeePerErg.
            /// The following invariants should hold:
            /// maxPriorityFeePerErg <= maxFeePerErg
            /// baseFee <= maxFeePerErg
            /// The operator shoud receive min(maxFeePerErg, baseFee + maxPriorityFeePerErg)
            function getErgsPrice(
                maxFeePerErg,
                maxPriorityFeePerErg
            ) -> ret {
                let baseFee := basefee()

                if gt(maxPriorityFeePerErg, maxFeePerErg) {
                    revertWithReason(
                        MAX_PRIORITY_FEE_PER_ERG_GREATER_THAN_MAX_FEE_PER_ERG(),
                        0
                    )
                }

                if gt(baseFee, maxFeePerErg) {
                    revertWithReason(
                        BASE_FEE_GREATER_THAN_MAX_FEE_PER_ERG(),
                        0
                    )
                }

                let maxFeeThatOperatorCouldTake := add(baseFee, maxPriorityFeePerErg)

                switch gt(maxFeeThatOperatorCouldTake, maxFeePerErg) 
                case 1 {
                    ret := maxFeePerErg
                }
                default {
                    ret := maxFeeThatOperatorCouldTake
                }
            }

            /// @dev The function responsible for processing L2 transactions.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            /// @param resultPtr The pointer at which the result of the execution of this transaction
            /// should be stored.
            /// @dev This function firstly does the validation step and then the execution step in separate near_calls.
            /// It is important that these steps are split to avoid rollbacking the state made by the validation step.
            function processL2Tx(
                txDataOffset,
                resultPtr,
            ) {
                let ergsBeforeValidate := gas()
                // Saving the tx hash and the suggested signed tx hash to memory
                saveTxHashes(txDataOffset)

                let innerTxDataOffset := add(txDataOffset, 32)
                let ergsLimit := getErgsLimit(innerTxDataOffset)
                debugLog("ergsLimit", ergsLimit)
                let validateABI := getNearCallABI(ergsLimit)

                let ergsPrice := getErgsPrice(getMaxFeePerErg(innerTxDataOffset), getMaxPriorityFeePerErg(innerTxDataOffset))

                checkEnoughGas(ergsLimit)
                // Note, that it is assumed that `ZKSYNC_NEAR_CALL_validateTx` will always return true
                // unless some error which made the whole bootloader to revert has happended or
                // it runs out of gas.
                let isValid := ZKSYNC_NEAR_CALL_validateTx(validateABI, txDataOffset, ergsPrice)

                let ergsUsedForValidate := sub(ergsBeforeValidate, gas())
                debugLog("ergsUsedForValidate", ergsUsedForValidate)
                
                if iszero(isValid) {
                    revertWithReason(TX_VALIDATION_OUT_OF_GAS(), 0)
                }

                let ergsLeft := sub(ergsLimit, ergsUsedForValidate)
                if lt(ergsLimit, ergsUsedForValidate) {
                    ergsLeft := 0
                }
                if lt(ergsLeft, MIN_LEFT_AFTER_VERIFY()) {
                    revertWithReason(TX_VALIDATION_OUT_OF_GAS(), 0)
                }

                setHook(VM_HOOK_VALIDATION_STEP_ENDED())

                let executeABI := getNearCallABI(ergsLeft)
                checkEnoughGas(ergsLeft)
                // for this one, we don't care whether or not it fails.
                let success := ZKSYNC_NEAR_CALL_executeL2Tx(
                    executeABI,
                    txDataOffset
                )
                
                mstore(resultPtr, success)
            }

            /// @dev Function responsible for the validation & fee payment step of the transaction. 
            /// @param abi The nearCall ABI. It is implicitly used as ergsLimit for the call of this function.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            /// @param ergsPrice The ergsPrice to be used in this transaction.
            function ZKSYNC_NEAR_CALL_validateTx(
                abi,
                txDataOffset,
                ergsPrice
            ) -> ret {
                // For the validation step we always use the bootloader as the tx.origin of the transaction
                setTxOrigin(BOOTLOADER_FORMAL_ADDR())
                setErgsPrice(ergsPrice)
                
                // Skipping the first 0x20 word of the ABI-encoding
                let innerTxDataOffset := add(txDataOffset, 32)
                debugLog("Starting validation", 0)

                markFactoryDepsForTx(innerTxDataOffset, false)
                accountValidateTx(txDataOffset)
                debugLog("Tx validation complete", 1)
                
                let from := getFrom(innerTxDataOffset)
                let ergsLimit := getErgsLimit(innerTxDataOffset)
                
                ensurePayment(txDataOffset, ergsPrice)
                
                ret := 1
            }

            /// @dev Function responsible for the execution of the L2 transaction.
            /// It includes both the call to the `executeTransaction` method of the account
            /// and the call to postOp of the account. 
            /// @param abi The nearCall ABI. It is implicitly used as ergsLimit for the call of this function.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            function ZKSYNC_NEAR_CALL_executeL2Tx(
                abi,
                txDataOffset
            ) -> success {
                // Skipping the first word of the ABI-encoding encoding
                let innerTxDataOffset := add(txDataOffset, 32)
                let from := getFrom(innerTxDataOffset)

                debugLog("Executing L2 tx", 0)
                // The tx.origin can only be an EOA
                switch isEOA(from)
                case true {
                    setTxOrigin(from)
                }  
                default {
                    setTxOrigin(BOOTLOADER_FORMAL_ADDR())
                }

                success := executeL2Tx(txDataOffset)
                debugLog("Executing L2 ret", success)

                let paymaster := getPaymaster(innerTxDataOffset)
                if paymaster {
                    // We don't care whether the call to paymaster succedes or not.
                    pop(callPostOp(
                        paymaster,
                        txDataOffset,
                        success,
                        // TODO (SMA-1220): refunds are not supported as of now
                        0
                    ))
                }

                // The overhead of repaying fees that should include the potential costs
                // of doing the transfer
                // TODO (SMA-1220): support refunds. They can work out of the box, but they were
                // TODO: calculate it dynamically depending on the ergsPerPubdataByte
                // removed for now, since most of the tests expect that the fee is ergsLimit * ergsPrice.
                // let REPAYING_FEES_OVERHEAD := 10000
                // let gasLeft := gas()
                // if gt(gasLeft, REPAYING_FEES_OVERHEAD) {
                //     // Returning back the funds to the operator.                       
                //     ensurePullETH(
                //         operatorAddress,
                //         from,
                //         mul(ergsPrice, sub(gasLeft, REPAYING_FEES_OVERHEAD)),
                //     )
                // }
            }

            /// @dev Function responsible for the execution of the L1->L2 transaction.
            /// @param abi The nearCall ABI. It is implicitly used as ergsLimit for the call of this function.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            function ZKSYNC_NEAR_CALL_executeL1Tx(
                abi,
                txDataOffset
            ) -> success {
                // Skipping the first word of the ABI encoding of the struct
                let innerTxDataOffset := add(txDataOffset, 0x20)
                let from := getFrom(innerTxDataOffset)
                let ergsPrice := getMaxFeePerErg(innerTxDataOffset)

                debugLog("Executing L1 tx", 0)
                debugLog("from", from)
                debugLog("ergsPrice", ergsPrice)

                // We assume that addresses of smart contracts on zkSync and Ethereum
                // never overlap, so no need to check whether `from` is an EOA here.
                debugLog("setting tx origin", from)

                setTxOrigin(from)
                debugLog("setting ergs price", ergsPrice)

                setErgsPrice(ergsPrice)

                debugLog("execution itself", 0)


                success := executeL1Tx(txDataOffset)
                debugLog("Executing L1 ret", success)
            }

            /// @dev Returns the ABI for nearCalls.
            /// @param ergsLimit The ergsLimit (gasLimit in EVM terms) for this nearCall
            function getNearCallABI(ergsLimit) -> ret {
                ret := ergsLimit
            }

            /// @dev Used to panic from the nearCall without reverting the parent frame.
            /// If you use `revert(...)`, the error will bubble up from the near call and
            /// make the bootloader to revert as well. This method allows to exit the nearCall only.
            function nearCallPanic() {
                // Here we exhaust all the ergs of the current frame.
                // This will cause the execution to panic.
                // Note, that it will cause only the inner call to panic.
                precompileCall(1000000000)
            }

            /// @dev Executes the `precompileCall` opcode. 
            /// Since the bootloader has no implicit meaning for this opcode,
            /// this method just burns ergs.
            function precompileCall(ergsToBurn) -> ret {
                ret := verbatim_2i_1o("precompile", 0, ergsToBurn)
            }
            
            /// @dev Returns the pointer to the latest returndata.
            function returnDataPtr() -> ret {
                ret := verbatim_0i_1o("get_global::ptr_return_data")
            }


            <!-- @if BOOTLOADER_TYPE=='playground_block' -->
            function ZKSYNC_NEAR_CALL_ethCall(
                abi,
                txDataOffset,
                resultPtr
            ) {
                let innerTxDataOffset := add(txDataOffset, 32)
                let to := getTo(innerTxDataOffset)
                let from := getFrom(innerTxDataOffset)
                
                debugLog("from: ", from)
                debugLog("to: ", to)

                switch isEOA(from)
                case true {
                    setTxOrigin(from)
                }
                default {
                    setTxOrigin(BOOTLOADER_FORMAL_ADDR())
                }

                let dataPtr := getDataPtr(innerTxDataOffset)
                markFactoryDepsForTx(innerTxDataOffset, false)
                
                let value := getReserved1(innerTxDataOffset)

                let success := msgValueSimulatorMimicCall(
                    to,
                    from,
                    value,
                    dataPtr
                )

                if iszero(success) {
                    // If success is 0, we need to revert
                    revertWithReason(
                        ETH_CALL_ERR_CODE(),
                        1
                    )
                }

                mstore(resultPtr, success)

                // Store results of the call in the memory.
                if success {                
                    let returnsize := returndatasize()
                    returndatacopy(0,0,returnsize)
                    return(0,returnsize)
                }

            }
            <!-- @endif -->

            /// @dev Given the pointer to the calldata, the value and to
            /// performs the call through the msg.value simulator.
            /// @param to Which contract to call
            /// @param from The `msg.sender` of the call.
            /// @param value The `value` that will be used in the call.
            /// @param dataPtr The pointer to the calldata of the transaction. It must store
            /// the length of the calldata and the calldata itself right afterwards.
            function msgValueSimulatorMimicCall(to, from, value, dataPtr) -> success {
                // Only calls to the deployer system contract are allowed to be system
                let isSystem := eq(to, CONTRACT_DEPLOYER_ADDR())

                success := mimicCallOnlyResult(
                    MSG_VALUE_SIMULATOR_ADDR(),
                    from, 
                    dataPtr,
                    0,
                    1,
                    getMsgValueSimulatorAbi1(value, isSystem),
                    to
                )
            }

            /// @dev Checks whether the current frame has enough gas
            function checkEnoughGas(gasToProvide) {
                if lt(gas(), gasToProvide) {
                    assertionError("not enough gas provided")
                }
            }

            /// @dev Returns the first extra abi param to be used by the L1MessageSimulator
            function getMsgValueSimulatorAbi1(value, isSystem) -> ret {
                if gt(value, sub(IS_SYSTEM_CALL_MSG_VALUE_BIT(), 1)) {
                    assertionError("Incorrect value")
                }

                switch isSystem
                case 1 {
                    ret := or(value, IS_SYSTEM_CALL_MSG_VALUE_BIT())
                }
                default {
                    ret := value
                }

            }

            /// @dev A method where all panics in the nearCalls get to.
            /// It is needed to prevent nearCall panics from bubbling up.
            function ZKSYNC_CATCH_NEAR_CALL() {
                debugLog("ZKSYNC_CATCH_NEAR_CALL",0)
                setHook(VM_HOOK_CATCH_NEAR_CALL())
            }
            
            /// @dev Prepends the selector before the txDataOffset,
            /// preparing it to be used to call either `verify` or `execute`.
            /// Returns the pointer to the calldata.
            /// Note, that this overrides 32 bytes before the current transaction:
            function prependSelector(txDataOffset, selector) -> ret {
                
                let calldataPtr := sub(txDataOffset, 4)
                // Note, that since `mstore` stores 32 bytes at once, we need to 
                // actually store the selector in one word starting with the 
                // (txDataOffset - 32) = (calldataPtr - 28)
                mstore(sub(calldataPtr, 28), selector)

                ret := calldataPtr
            }

            /// @dev Returns the minimum of two numbers
            function min(x,y) -> ret {
                ret := y
                if lt(x,y) {
                    ret := x
                }
            }

            /// @dev Checks whether an address is an account
            /// @param addr The address to check
            function ensureAccount(addr) {
                mstore(0, {{RIGHT_PADDED_GET_ACCOUNT_VERSION_SELECTOR}})
                mstore(4, addr)

                let success := call(
                    gas(),
                    CONTRACT_DEPLOYER_ADDR(),
                    0,
                    0,
                    36,
                    0,
                    32
                )

                let supportedVersion := mload(0)

                if iszero(success) {
                    revertWithReason(
                        FAILED_TO_CHECK_ACCOUNT_ERR_CODE(),
                        1
                    )
                }

                // Currently only two versions are supported: 1 or 0, which basically 
                // mean whether the contract is an account or not.
                if iszero(supportedVersion) {
                    revertWithReason(
                        FROM_IS_NOT_AN_ACCOUNT_ERR_CODE(),
                        0
                    )
                }
            }

            /// @dev Checks whether an address is an EOA (i.e. has not code deployed on it)
            /// @param addr The address to check
            function isEOA(addr) -> ret {
                mstore(0, {{GET_RAW_CODE_HASH_SELECTOR}})
                mstore(4, addr)
                let success := call(
                    gas(),
                    ACCOUNT_CODE_STORAGE_ADDR(),
                    0,
                    0,
                    36,
                    0,
                    32
                )

                if iszero(success) {
                    // The call to the account code storage should always succeed
                    nearCallPanic()
                }

                let rawCodeHash := mload(0)

                ret := iszero(rawCodeHash)
            }

            /// @dev Calls the `payForTransaction` method of an account
            function accountPayForTx(account, txDataOffset) -> success {
                success := callAccountMethod({{PAY_FOR_TX_SELECTOR}}, account, txDataOffset)
            }

            /// @dev Calls the `prepareForPaymaster` method of an account
            function accountPrePaymaster(account, txDataOffset) -> success {
                success := callAccountMethod({{PRE_PAYMASTER_SELECTOR}}, account, txDataOffset)
            }

            /// @dev Calls the `validateAndPayForPaymasterTransaction` method of a paymaster
            function validateAndPayForPaymasterTransaction(paymaster, txDataOffset) -> success {
                success := callAccountMethod({{VALIDATE_AND_PAY_PAYMASTER}}, paymaster, txDataOffset)
            }

            /// @dev Used to call a method with the following signature;
            /// someName( 
            ///     bytes32 _txHash,
            ///     bytes32 _suggestedSignedHash, 
            ///     Transaction calldata _transaction
            /// )
            // Note, that this method expects that the current tx hashes are already stored 
            // in the `CURRENT_L2_TX_HASHES` slots.
            function callAccountMethod(selector, account, txDataOffset) -> success {
                // Safety invariant: it is safe to override data stored under 
                // `txDataOffset`, since the account methods are called only using 
                // `callAccountMethod` or `callPostOp` methods, both of which reformat
                // the contents before innerTxDataOffset (i.e. txDataOffset + 32 bytes),
                // i.e. make sure that the position at the txDataOffset has valid value.
                let txDataWithHashesOffset := sub(txDataOffset, 64)

                // First word contains the canonical tx hash
                let currentL2TxHashesPtr := CURRENT_L2_TX_HASHES_BEGIN_BYTE()
                mstore(txDataWithHashesOffset, mload(currentL2TxHashesPtr))

                // Second word contains the suggested tx hash for verifying
                // signatures.
                currentL2TxHashesPtr := add(currentL2TxHashesPtr, 32)
                mstore(add(txDataWithHashesOffset, 32), mload(currentL2TxHashesPtr))

                // Third word contains the offset of the main tx data (it is always 96 in our case)
                mstore(add(txDataWithHashesOffset, 64), 96)

                let calldataPtr := prependSelector(txDataWithHashesOffset, selector)
                let txInnerDataOffset := add(txDataOffset, 32)

                let len := getDataLength(txInnerDataOffset)

                // Besides the length of the transaction itself,
                // we also require 3 words for hashes and the offset
                // of the inner tx data.
                let fullLen := add(len, 100)

                // The call itself.
                success := call(
                    gas(), // The number of ergs to pass.
                    account, // The address to call.
                    0, // The `value` to pass.
                    calldataPtr, // The pointer to the calldata.
                    fullLen, // The size of the calldata, which is 4 for the selector + the actual length of the struct.
                    0, // The pointer where the returned data will be written.
                    0 // The output has size of 32 (a single bool is expected)
                )
            }

            /// @dev Calculates and saves the explorer hash and the suggested signed hash for the transaction.
            function saveTxHashes(txDataOffset) {
                let calldataPtr := prependSelector(txDataOffset, {{GET_TX_HASHES_SELECTOR}})
                let txInnerDataOffset := add(txDataOffset, 32)

                let len := getDataLength(txInnerDataOffset)

                // The first word is formal, but still required by the ABI
                // We also should take into account the selector.
                let fullLen := add(len, 36)

                // The call itself.
                let success := call(
                    gas(), // The number of ergs to pass.
                    BOOTLOADER_UTILITIES(), // The address to call.
                    0, // The `value` to pass.
                    calldataPtr, // The pointer to the calldata.
                    fullLen, // The size of the calldata, which is 4 for the selector + the actual length of the struct.
                    CURRENT_L2_TX_HASHES_BEGIN_BYTE(), // The pointer where the returned data will be written.
                    64 // The output has size of 32 (signed tx hash and explorer tx hash are expected)
                )

                if iszero(success) {
                    revertWithReason(
                        ACCOUNT_TX_VALIDATION_ERR_CODE(),
                        1
                    )
                }

                if iszero(eq(returndatasize(), 64)) {
                    assertionError("saveTxHashes: returndata invalid")
                }
            }

            /// @dev Encodes and calls the postOp method of the contract.
            /// Note, that it *breaks* the contents of the previous transactions.
            /// @param paymaster The address of the paymaster
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            /// @param txResult The status of the transaction (0 if succeeded, 1 otherwise).
            /// @param maxRefundedErgs The maximum number of ergs the bootloader can be refunded. 
            /// This is the `maximum` number because it does not take into account the number of ergs that
            /// can be spent by the paymaster itself.
            function callPostOp(paymaster, txDataOffset, txResult, maxRefundedErgs) -> success {
                // The postOp method has the following signature:
                // function postTransaction(
                //     bytes calldata _context,
                //     Transaction calldata _transaction,
                //     bytes32 _txHash,
                //     bytes32 _suggestedSignedHash,
                //     ExecutionResult _txResult,
                //     uint256 _maxRefundedErgs
                // ) external payable;
                // The encoding is the following:
                // 1. Offset to the _context's content. (32 bytes)
                // 2. Offset to the _transaction's content. (32 bytes)
                // 3. _txHash (32 bytes)
                // 4. _suggestedSignedHash (32 bytes)
                // 5. _txResult (32 bytes)
                // 6. _maxRefundedErgs (32 bytes)
                // 7. _context (note, that the content must be padded to 32 bytes)
                // 8. _transaction
                
                let contextLen := mload(PAYMASTER_CONTEXT_BEGIN_BYTE())
                let paddedContextLen := lengthToWords(contextLen)
                // The length of selector + the first 7 fields (with context len) + context itself.
                let preTxLen := add(228, paddedContextLen)

                let innerTxDataOffset := add(txDataOffset, 0x20)
                let calldataPtr := sub(innerTxDataOffset, preTxLen)

                {
                    let ptr := calldataPtr

                    // Selector
                    mstore(ptr, {{PADDED_POST_TRANSACTION_SELECTOR}})
                    ptr := add(ptr, 4)
                    
                    // context ptr
                    mstore(ptr, 192) // The context always starts at 32 * 6 position
                    ptr := add(ptr, 32)
                    
                    // transaction ptr
                    mstore(ptr, sub(innerTxDataOffset, add(calldataPtr, 4)))
                    ptr := add(ptr, 32)

                    // tx hash
                    mstore(ptr, mload(CURRENT_L2_TX_HASHES_BEGIN_BYTE()))
                    ptr := add(ptr, 32)

                    // suggested signed hash
                    mstore(ptr, mload(add(CURRENT_L2_TX_HASHES_BEGIN_BYTE(), 32))
                    ptr := add(ptr, 32)

                    // tx result
                    mstore(ptr, txResult)
                    ptr := add(ptr, 32)

                    // maximal refunded ergs
                    mstore(ptr, maxRefundedErgs)
                    ptr := add(ptr, 32)

                    // storing context itself
                    memCopy(PAYMASTER_CONTEXT_BEGIN_BYTE(), ptr, add(32, paddedContextLen))
                    ptr := add(ptr, add(32, paddedContextLen))

                    // At this point, the ptr should reach the innerTxDataOffset. 
                    // If not, we have done something wrong here.
                    if iszero(eq(ptr, innerTxDataOffset)) {
                        assertionError("postOp: ptr != innerTxDataOffset")
                    }
                    
                    // no need to store the transaction as from the innerTxDataOffset starts
                    // valid encoding of the transaction
                }

                let calldataLen := add(preTxLen, getDataLength(innerTxDataOffset))
                
                success := call(
                    gas(),
                    paymaster,
                    0,
                    calldataPtr,
                    calldataLen,
                    0,
                    0
                )
            }

            /// @dev Copies [from..from+len] to [to..to+len]
            /// Note, that len must be divisible by 32.
            function memCopy(from, to, len) {
                // Ensuring that len is always divisible by 32.
                if mod(len, 32) {
                    assertionError("Memcopy with unaligned length")
                }

                let finalFrom := add(from, len)

                for { } lt(from, finalFrom) { 
                    from := add(from, 32)
                    to := add(to, 32)
                } {
                    mstore(to, mload(from))
                }
            }

            /// @dev Validates the transaction again the senders' account.
            /// Besides ensuring that the contract agrees to a transaction,
            /// this method also enforces that the nonce has been marked as used.
            function accountValidateTx(txDataOffset) {
                // Skipping the first 0x20 word of the ABI-encoding of the struct
                let txInnerDataOffset := add(txDataOffset, 32)
                let from := getFrom(txInnerDataOffset)
                ensureAccount(from)

                // The nonce should be unique for each transaction.
                let nonce := getReserved0(txInnerDataOffset)
                // Here we check that this nonce was not available before the validation step
                ensureNonceUsage(from, nonce, 0)

                setHook(VM_HOOK_ACCOUNT_VALIDATION_ENTERED())
                debugLog("pre-validate",0)
                debugLog("pre-validate",from)
                let success := callAccountMethod({{VALIDATE_TX_SELECTOR}}, from, txDataOffset)
                setHook(VM_HOOK_NO_VALIDATION_ENTERED())

                if iszero(success) {
                    revertWithReason(
                        ACCOUNT_TX_VALIDATION_ERR_CODE(),
                        1
                    )
                }
                
                // Here we make sure that the nonce is no longer available after the validation step
                ensureNonceUsage(from, nonce, 1)
            }

            /// @dev Calls the KnownCodesStorage system contract to mark the factory dependencies of 
            /// the transaction as known.
            function markFactoryDepsForTx(innerTxDataOffset, isL1Tx) {
                debugLog("starting factory deps", 0)
                let factoryDepsPtr := getFactoryDepsPtr(innerTxDataOffset)
                let factoryDepsLength := mload(factoryDepsPtr)
                
                if gt(factoryDepsLength, MAX_NEW_FACTORY_DEPS()) {
                    assertionError("too many factory deps")
                }

                let ptr := NEW_FACTORY_DEPS_BEGIN_BYTE()
                // Selector
                mstore(ptr, {{MARK_BATCH_AS_REPUBLISHED_SELECTOR}})
                ptr := add(ptr, 32)

                // Saving whether the dependencies should be sent on L1
                // There is no need to send them for L1 transactions, since their
                // preimages are already available on L1.
                mstore(ptr, iszero(isL1Tx))
                ptr := add(ptr, 32)

                // Saving the offset to array (it is always 64)
                mstore(ptr, 64)
                ptr := add(ptr, 32)

                // Saving the array

                // We also need to include 32 bytes for the length itself
                let arrayLengthBytes := add(32, mul(factoryDepsLength, 32))
                // Copying factory deps array
                memCopy(factoryDepsPtr, ptr, arrayLengthBytes)
    
                let success := call(
                    gas(),
                    KNOWN_CODES_CONTRACT_ADDR(),
                    0,
                    // Shifting by 28 to start from the selector
                    add(NEW_FACTORY_DEPS_BEGIN_BYTE(), 28),
                    // 4 (selector) + 32 (send to l1 flag) + 32 (factory deps offset)+ 32 (factory deps length)
                    add(100, mul(factoryDepsLength, 32)),
                    0,
                    0
                )

                debugLog("factory deps success", success)

                if iszero(success) {
                    debugReturndata()
                    revertWithReason(
                        FAILED_TO_MARK_FACTORY_DEPS(),
                        1
                    )
                }
            }

            /// @dev Function responsible for executing the L1->L2 transactions.
            function executeL1Tx(txDataOffset) -> ret {
                // Skipping the formal 0x20 word of the ABI encoding.
                let innerTxDataOffset := add(txDataOffset, 32)
                let to := getTo(innerTxDataOffset)
                debugLog("to", to)
                let from := getFrom(innerTxDataOffset)
                debugLog("from", from)
                let value := getReserved1(innerTxDataOffset)
                debugLog("value", from)
                let dataPtr := getDataPtr(innerTxDataOffset)
                
                let dataLength := mload(dataPtr)
                let data := add(dataPtr, 32)

                ret := msgValueSimulatorMimicCall(
                    to,
                    from,
                    value,
                    dataPtr
                )

                if iszero(ret) {
                    debugReturndata()
                }
            }

            /// @dev Function responsible for the execution of the L2 transaction 
            /// @dev Returns `true` or `false` depending on whether or not the tx has reverted.
            function executeL2Tx(txDataOffset) -> ret {
                let innerTxDataOffset := add(txDataOffset, 32)
                let from := getFrom(innerTxDataOffset)
                ret := callAccountMethod({{EXECUTE_TX_SELECTOR}}, from, txDataOffset)
                
                if iszero(ret) {
                    debugReturndata()
                }
            }

            ///
            /// zkSync-specific utilities:
            ///

            /// @dev Returns an ABI that can be used for low-level 
            /// invocations of calls and mimicCalls
            /// @param dataPtr The pointer to the calldata.
            /// @param ergsPassed The number of ergs (gas) to be passed with the call.
            /// @param shardId The shard id of the callee. Currently only `0` (Rollup) is supported.
            /// @param forwardingMode The mode of how the calldata is forwarded 
            /// It is possible to either pass a pointer, slice of auxheap or heap. For the
            /// bootloader purposes using heap (0) is enough.
            /// @param isConstructorCall Whether the call should contain the isConstructor flag.
            /// @param isSystemCall Whether the call should contain the isSystemCall flag.
            /// @return ret The ABI
            function getFarCallABI(
                dataPtr,
                ergsPassed,
                shardId,
                forwardingMode,
                isConstructorCall,
                isSystemCall,
            ) -> ret {
                let dataOffset := 0
                let memoryPage := 0
                let dataStart := add(dataPtr, 0x20)
                let dataLength := mload(dataPtr)

                ret := shl(0, dataOffset)
                ret := or(ret, shl(32, memoryPage))
                ret := or(ret, shl(64, dataStart))
                ret := or(ret, shl(96, dataLength))

                ret := or(ret, shl(192, ergsPassed))
                ret := or(ret, shl(224, shardId))
                ret := or(ret, shl(232, forwardingMode))
                ret := or(ret, shl(240, isConstructorCall))
                ret := or(ret, shl(248, isSystemCall))
            }

            /// @dev Does mimicCall without copying the returndata.
            /// @param to Who to call
            /// @param whoToMimic The `msg.sender` of the call
            /// @param data The pointer to the calldata
            /// @param isConstructor Whether the call should contain the isConstructor flag
            /// @param isSystemCall Whether the call should contain the isSystem flag.
            /// @param extraAbi1 The first extraAbiParam
            /// @param extraAbi2 The second extraAbiParam
            /// @return ret 1 if the call was successful, 0 otherwise.
            function mimicCallOnlyResult(
                to,
                whoToMimic,
                data,
                isConstructor,
                isSystemCall,
                extraAbi1,
                extraAbi2
            ) -> ret {
                let farCallAbi := getFarCallABI(
                    data,
                    gas(),
                    // Only rollup is supported for now
                    0,
                    0,
                    isConstructor,
                    isSystemCall
                )

                ret := verbatim_5i_1o("system_mimic_call", to, whoToMimic, farCallAbi, extraAbi1, extraAbi2) 
            }
            
            <!-- @if BOOTLOADER_TYPE=='playground_block' -->
            // Extracts the required byte from the 32-byte word.
            // 31 would mean the MSB, 0 would mean LSB.
            function getWordByte(word, byteIdx) -> ret {
                // Shift the input to the right so the required byte is LSB
                ret := shr(mul(8, byteIdx), word)
                // Clean everything else in the word
                ret := and(ret, 0xFF)
            }
            <!-- @endif -->


            /// @dev Sends an L2->L1 log.
            /// @param isService The isService flag of the call.
            /// @param key The `key` parameter of the log.
            /// @param value The `value` parameter of the log.
            function sendToL1(isService, key, value) {
                verbatim_3i_0o("to_l1", isService, key, value)
            } 
            
            /// @dev Increment the number of txs in the block
            function considerNewTx() {
                verbatim_0i_0o("increment_tx_counter")
            }

            /// @dev Set the new price per pubdata byte
            function setPricePerPubdataByte(newPrice) {
                verbatim_1i_0o("set_pubdata_price", newPrice)
            }

            /// @dev Set the new value for the tx origin context value
            function setTxOrigin(newTxOrigin) -> success {
                let success := setContextVal({{RIGHT_PADDED_SET_TX_ORIGIN}}, newTxOrigin)

                if iszero(success) {
                    debugLog("Failed to set txOrigin", newTxOrigin)    
                    nearCallPanic()
                }
            }

            /// @dev Set the new value for the tx origin context value
            function setErgsPrice(newGasPrice) {
                let success := setContextVal({{PADDED_SET_ERGS_PRICE}}, newGasPrice)

                if iszero(success) {
                    debugLog("Failed to set gas price", newGasPrice)
                    nearCallPanic()
                }
            }

            /// @notice Sets the context information for the current block.
            /// @dev The SystemContext.sol system contract is responsible for validating
            /// the validity of the new block's data.
            function setNewBlock(prevBlockHash, newTimestamp, newBlockNumber) {
                mstore(0, {{SET_NEW_BLOCK_SELECTOR}})
                mstore(4, prevBlockHash)
                mstore(36, newTimestamp)
                mstore(68, newBlockNumber)

                let success := call(
                    gas(),
                    SYSTEM_CONTEXT_ADDR(),
                    0,
                    0,
                    100,
                    0,
                    0
                )

                if iszero(success) {
                    debugLog("Failed to set new block: ", prevBlockHash)
                    debugLog("Failed to set new block: ", newTimestamp)

                    revertWithReason(FAILED_TO_SET_NEW_BLOCK_ERR_CODE(), 1)
                }
            }

            <!-- @if BOOTLOADER_TYPE!='proved_block' -->
            /// @notice Arbitrarily overrides the current block information.
            /// @dev It should NOT be available in the proved block. 
            function unsafeOverrideBlock(newTimestamp, newBlockNumber) {
                mstore(0, {{OVERRIDE_BLOCK_SELECTOR}})
                mstore(4, newTimestamp)
                mstore(36, newBlockNumber)

                let success := call(
                    gas(),
                    SYSTEM_CONTEXT_ADDR(),
                    0,
                    0,
                    68,
                    0,
                    0
                )

                if iszero(success) {
                    debugLog("Failed to override block: ", newTimestamp)
                    debugLog("Failed to override block: ", newBlockNumber)

                    revertWithReason(FAILED_TO_SET_NEW_BLOCK_ERR_CODE(), 1)
                }
            }
            <!-- @endif -->


            // Checks whether the nonce `nonce` have been already used for 
            // account `from`. Reverts if the nonce has not been used properly.
            function ensureNonceUsage(from, nonce, shouldNonceBeUsed) {
                // INonceHolder.validateNonceUsage selector
                mstore(0, {{VALIDATE_NONCE_USAGE_PADDED_SELECTOR}})
                mstore(4, from)
                mstore(36, nonce)
                mstore(68, shouldNonceBeUsed)

                let success := call(
                    gas(),
                    NONCE_HOLDER_ADDR(),
                    0,
                    0,
                    100,
                    0,
                    0
                )

                if iszero(success) {
                    revertWithReason(
                        ACCOUNT_TX_VALIDATION_ERR_CODE(),
                        1
                    )
                }
            }

            /// @dev Encodes and performs a call to a method of
            /// `SystemContext.sol` system contract of the roughly the following interface:
            /// someMethod(uint256 val)
            function setContextVal(
                selector,
                value,
            ) -> ret {
                mstore(0, selector)
                mstore(4, value)

                ret := call(
                    gas(),
                    SYSTEM_CONTEXT_ADDR(),
                    0,
                    0,
                    36,
                    0,
                    0
                )
            }

            // Each of the txs have the following type:
            // struct Transaction {
            //     // The type of the transaction.
            //     uint256 txType;
            //     // The caller.
            //     uint256 from;
            //     // The callee.
            //     uint256 to;
            //     // The ergsLimit to pass with the transaction. 
            //     // It has the same meaning as Ethereum's gasLimit.
            //     uint256 ergsLimit;
            //     // The maximum amount of ergs the user is willing to pay for a byte of pubdata.
            //     uint256 ergsPerPubdataByteLimit;
            //     // The maximum fee per erg that the user is willing to pay. 
            //     // It is akin to EIP1559's maxFeePerGas.
            //     uint256 maxFeePerErg;
            //     // The maximum priority fee per erg that the user is willing to pay. 
            //     // It is akin to EIP1559's maxPriorityFeePerGas.
            //     uint256 maxPriorityFeePerErg;
            //     // The transaction's paymaster. If there is no paymaster, it is equal to 0.
            //     uint256 paymaster;
            //     // In the future, we might want to add some
            //     // new fields to the struct. The `txData` struct
            //     // is to be passed to account and any changes to its structure
            //     // would mean a breaking change to these accounts. In order to prevent this,
            //     // we should keep some fields as "reserved".
            //     // It is also recommneded that their length is fixed, since
            //     // it would allow easier proof integration (in case we will need
            //     // some special circuit for preprocessing transactions).
            //     uint256[6] reserved;
            //     // The transaction's calldata.
            //     bytes data;
            //     // The signature of the transaction.
            //     bytes signature;
            //     // The properly formatted hashes of bytecodes that must be published on L1
            //     // with the inclusion of this transaction. Note, that a bytecode has been published
            //     // before, the user won't pay fees for its republishing.
            //     bytes32[] factoryDeps;
            //     // The input to the paymaster.
            //     bytes paymasterInput;
            //     // Reserved dynamic type for the future use-case. Using it should be avoided,
            //     // But it is still here, just in case we want to enable some additional functionality.
            //     bytes reservedDynamic;
            // }

            /// @notice Asserts the equality of two values and reverts 
            /// with the appropriate error message in case it doesn't hold
            /// @param value1 The first value of the assertion
            /// @param value2 The second value of the assertion
            /// @param message The error message
            function assertEq(value1, value1, message) {
                switch eq(value1, value1) 
                    case 0 { assertionError(message) }
                    default { } 
            }

            /// @notice Makes sure that the structure of the transaction is set in accordance to its type
            /// @dev This function validates only L2 transactions, since the integrity of the L1->L2
            /// transactions is enforced by the L1 smart contracts.
            function validateTypedTxStructure(innerTxDataOffset) -> valid {
                /// Some common checks for all transactions.
                let reservedDynamicLength := getReservedDynamicBytesLength(innerTxDataOffset)
                if gt(reservedDynamicLength, 0) {
                    assertionError("non-empty reservedDynamic")
                }


                // In all of the L2 transactions, the following reserved fields are used:
                // reserved0 for nonce
                // reserved1 for value
                let txType := getTxType(innerTxDataOffset)
                switch txType
                    case 0 {
                        let maxFeePerErgs := getMaxFeePerErg(innerTxDataOffset)
                        let maxPriorityFeePerErg := getMaxPriorityFeePerErg(innerTxDataOffset)
                        assertEq(maxFeePerErgs, maxPriorityFeePerErg, "EIP1559 params wrong")
                        
                        // Here, for type 0 transactions the reserved2 field is used as a marker  
                        // whether the transaction should include chainId in its encoding. 
                        assertEq(getPaymaster(innerTxDataOffset), 0, "paymaster non zero")
                        assertEq(getReserved3(innerTxDataOffset), 0, "reserved3 non zero")
                        assertEq(getReserved4(innerTxDataOffset), 0, "reserved4 non zero")
                        assertEq(getReserved5(innerTxDataOffset), 0, "reserved5 non zero")
                        assertEq(getPaymasterInputBytesLength(innerTxDataOffset), 0, "paymasterInput non zero")
                    }
                    case 1 {
                        let maxFeePerErgs := getMaxFeePerErg(innerTxDataOffset)
                        let maxPriorityFeePerErg := getMaxPriorityFeePerErg(innerTxDataOffset)
                        assertEq(maxFeePerErgs, maxPriorityFeePerErg, "EIP1559 params wrong")
                        
                        assertEq(getPaymaster(innerTxDataOffset), 0, "paymaster non zero")
                        assertEq(getReserved2(innerTxDataOffset), 0, "reserved2 non zero")
                        assertEq(getReserved3(innerTxDataOffset), 0, "reserved3 non zero")
                        assertEq(getReserved4(innerTxDataOffset), 0, "reserved4 non zero")
                        assertEq(getReserved5(innerTxDataOffset), 0, "reserved5 non zero")
                        assertEq(getPaymasterInputBytesLength(innerTxDataOffset), 0, "paymasterInput non zero")
                    }
                    case 2 {
                        assertEq(getPaymaster(innerTxDataOffset), 0, "paymaster non zero")
                        assertEq(getReserved2(innerTxDataOffset), 0, "reserved2 non zero")
                        assertEq(getReserved3(innerTxDataOffset), 0, "reserved3 non zero")
                        assertEq(getReserved4(innerTxDataOffset), 0, "reserved4 non zero")
                        assertEq(getReserved5(innerTxDataOffset), 0, "reserved5 non zero")
                        assertEq(getPaymasterInputBytesLength(innerTxDataOffset), 0, "paymasterInput non zero")
                    }
                    case 112 {
                        assertEq(getReserved2(innerTxDataOffset), 0, "reserved2 non zero")
                        assertEq(getReserved3(innerTxDataOffset), 0, "reserved3 non zero")
                        assertEq(getReserved4(innerTxDataOffset), 0, "reserved4 non zero")
                        assertEq(getReserved5(innerTxDataOffset), 0, "reserved5 non zero")
                    }
                    case 255 {
                        // L1 transaction, no need to validate as it is validated on L1. 
                    }
            }

            /// 
            /// TransactionData utilities
            /// 
            /// @dev The next methods are programmatically generated
            ///

            function getTxType(innerTxDataOffset) -> ret {
                ret := mload(innerTxDataOffset)
            }
    
            function getFrom(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 32))
            }
    
            function getTo(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 64))
            }
    
            function getErgsLimit(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 96))
            }
    
            function getErgsPerPubdataByteLimit(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 128))
            }
    
            function getMaxFeePerErg(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 160))
            }
    
            function getMaxPriorityFeePerErg(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 192))
            }
    
            function getPaymaster(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 224))
            }
    
            function getReserved0(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 256))
            }
    
            function getReserved1(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 288))
            }
    
            function getReserved2(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 320))
            }
    
            function getReserved3(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 352))
            }
    
            function getReserved4(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 384))
            }
    
            function getReserved5(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 416))
            }
    
            function getDataPtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 448))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getDataBytesLength(innerTxDataOffset) -> ret {
                let ptr := getDataPtr(innerTxDataOffset)
                ret := lengthToWords(mload(ptr))
            }
    
            function getSignaturePtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 480))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getSignatureBytesLength(innerTxDataOffset) -> ret {
                let ptr := getSignaturePtr(innerTxDataOffset)
                ret := lengthToWords(mload(ptr))
            }
    
            function getFactoryDepsPtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 512))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getFactoryDepsBytesLength(innerTxDataOffset) -> ret {
                let ptr := getFactoryDepsPtr(innerTxDataOffset)
                ret := mul(mload(ptr),32)
            }
    
            function getPaymasterInputPtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 544))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getPaymasterInputBytesLength(innerTxDataOffset) -> ret {
                let ptr := getPaymasterInputPtr(innerTxDataOffset)
                ret := lengthToWords(mload(ptr))
            }
    
            function getReservedDynamicPtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 576))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getReservedDynamicBytesLength(innerTxDataOffset) -> ret {
                let ptr := getReservedDynamicPtr(innerTxDataOffset)
                ret := lengthToWords(mload(ptr))
            }
    
            /// This method checks that the transaction's structure is correct
            /// and tightly packed
            function validateAbiEncoding(innerTxDataOffset) -> ret {
                let fromValue := getFrom(innerTxDataOffset)
                if iszero(validateAddress(fromValue)) {
                    assertionError("Encoding from")
                }
    
                let toValue := getTo(innerTxDataOffset)
                if iszero(validateAddress(toValue)) {
                    assertionError("Encoding to")
                }
    
                let ergsLimitValue := getErgsLimit(innerTxDataOffset)
                if iszero(validateUint32(ergsLimitValue)) {
                    assertionError("Encoding ergsLimit")
                }
    
                let ergsPerPubdataByteLimitValue := getErgsPerPubdataByteLimit(innerTxDataOffset)
                if iszero(validateUint32(ergsPerPubdataByteLimitValue)) {
                    assertionError("Encoding ergsPerPubdataByteLimit")
                }
    
                let paymasterValue := getPaymaster(innerTxDataOffset)
                if iszero(validateAddress(paymasterValue)) {
                    assertionError("Encoding paymaster")
                }

                let expectedDynamicLenPtr := add(innerTxDataOffset, 608)
                
                let dataLengthPos := getDataPtr(innerTxDataOffset)
                if iszero(eq(dataLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding data")
                }
                expectedDynamicLenPtr := validateBytes(dataLengthPos)
        
                let signatureLengthPos := getSignaturePtr(innerTxDataOffset)
                if iszero(eq(signatureLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding signature")
                }
                expectedDynamicLenPtr := validateBytes(signatureLengthPos)
        
                let factoryDepsLengthPos := getFactoryDepsPtr(innerTxDataOffset)
                if iszero(eq(factoryDepsLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding factoryDeps")
                }
                expectedDynamicLenPtr := validateBytes32Array(factoryDepsLengthPos)

                let paymasterInputLengthPos := getPaymasterInputPtr(innerTxDataOffset)
                if iszero(eq(paymasterInputLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding paymasterInput")
                }
                expectedDynamicLenPtr := validateBytes(paymasterInputLengthPos)

                let reservedDynamicLengthPos := getReservedDynamicPtr(innerTxDataOffset)
                if iszero(eq(reservedDynamicLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding reservedDynamic")
                }
                expectedDynamicLenPtr := validateBytes(reservedDynamicLengthPos)

                ret := expectedDynamicLenPtr
            }

            function getDataLength(innerTxDataOffset) -> ret {
                // To get the length of the txData in bytes, we can simply
                // get the number of fields * 32 + the length of the dynamic types
                // in bytes.
                ret := 768

                ret := add(ret, getDataBytesLength(innerTxDataOffset))        
                ret := add(ret, getSignatureBytesLength(innerTxDataOffset))
                ret := add(ret, getFactoryDepsBytesLength(innerTxDataOffset))
                ret := add(ret, getPaymasterInputBytesLength(innerTxDataOffset))
                ret := add(ret, getReservedDynamicBytesLength(innerTxDataOffset))
            }

            /// 
            /// End of programmatically generated code
            ///
    
            /// @dev Accepts an address and returns whether or not it is
            /// a valid address
            function validateAddress(addr) -> ret {
                ret := lt(addr, shl(160, 1))
            }

            /// @dev Accepts an uint32 and returns whether or not it is
            /// a valid uint32
            function validateUint32(x) -> ret {
                ret := lt(x, shl(32,1))
            }

            /// Validates that's the `bytes` is formed correctly
            /// and returns the pointer right after the end of the bytes
            function validateBytes(bytesPtr) -> bytesEnd {
                let length := mload(bytesPtr)
                let lastWordBytes := mod(length, 32)

                switch lastWordBytes
                case 0 { 
                    // If the length is divisible by 32, then 
                    // the bytes occupy whole words, so there is
                    // nothing to validate
                    bytesEnd := add(bytesPtr, add(length, 32)) 
                }
                default {
                    // If the length is not divisible by 32, then 
                    // the last word is padded with zeroes, i.e.
                    // the last 32 - `lastWordBytes` bytes must be zeroes
                    // The easiest way to check this is to use AND operator

                    let zeroBytes := sub(32, lastWordBytes)
                    // It has its first 32 - `lastWordBytes` bytes set to 255
                    let mask := sub(shl(mul(zeroBytes,8),1),1)

                    let fullLen := lengthToWords(length)
                    bytesEnd := add(bytesPtr, add(32, fullLen))

                    let lastWord := mload(sub(bytesEnd, 32))

                    // If last word contains some unintended bits
                    // return 0
                    if and(lastWord, mask) {
                        assertionError("bad bytes encoding")
                    }
                }
            }

            /// @dev Accepts the pointer to the bytes32[] array length and 
            /// returns the pointer right after the array's content 
            function validateBytes32Array(arrayPtr) -> arrayEnd {
                // The bytes32[] array takes full words which may contain any content.
                // Thus, there is nothing to validate.
                let length := mload(arrayPtr)
                arrayEnd := add(arrayPtr, add(32, mul(length, 32)))
            }

            ///
            /// Debug utilities
            ///

            /// @notice A method used to prevent optimization of x by the compiler
            /// @dev This method is only used for logging purposes 
            function nonOptimized(x) -> ret {
                // value() is always 0 in bootloader context.
                ret := add(mul(callvalue(),x),x)
            }

            /// @dev This method accepts the message and some 1-word data associated with it
            /// It triggers a VM hook that allows the server to observe the behaviour of the system.
            function debugLog(msg, data) {
                storeVmHookParam(0, nonOptimized(msg))
                storeVmHookParam(1, nonOptimized(data))
                setHook(nonOptimized(VM_HOOK_DEBUG_LOG()))
            }

            /// @dev Triggers a hook that displays the returndata on the server side.
            function debugReturndata() {
                debugLog("returndataptr", returnDataPtr())
                storeVmHookParam(0, returnDataPtr()) 
                setHook(VM_HOOK_DEBUG_RETURNDATA())
            }
            
            /// 
            /// Error codes used for more correct diagnostics from the server side.
            /// 
        
            function ETH_CALL_ERR_CODE() -> ret {
                ret := 0
            }   

            function ACCOUNT_TX_VALIDATION_ERR_CODE() -> ret {
                ret := 1
            }

            function FAILED_TO_CHARGE_FEE_ERR_CODE() -> ret {
                ret := 2
            }

            function FROM_IS_NOT_AN_ACCOUNT_ERR_CODE() -> ret {
                ret := 3
            }

            function FAILED_TO_CHECK_ACCOUNT_ERR_CODE() -> ret {
                ret := 4
            }

            function UNACCEPTABLE_ERGS_PRICE_ERR_CODE() -> ret {
                ret := 5
            }

            function FAILED_TO_SET_NEW_BLOCK_ERR_CODE() -> ret {
                ret := 6
            }

            function PAY_FOR_TX_FAILED_ERR_CODE() -> ret {
                ret := 7
            }

            function PRE_PAYMASTER_PREPARATION_FAILED_ERR_CODE() -> ret {
                ret := 8
            }

            function PAYMASTER_VALIDATION_FAILED_ERR_CODE() -> ret {
                ret := 9
            }

            function FAILED_TO_SEND_FEES_TO_THE_OPERATOR() -> ret {
                ret := 10
            }

            function UNACCEPTABLE_PUBDATA_PRICE_ERR_CODE() -> ret {
                ret := 11
            }

            function TX_VALIDATION_FAILED_ERR_CODE() -> ret {
                ret := 12
            }

            function MAX_PRIORITY_FEE_PER_ERG_GREATER_THAN_MAX_FEE_PER_ERG() -> ret {
                ret := 13
            }

            function BASE_FEE_GREATER_THAN_MAX_FEE_PER_ERG() -> ret {
                ret := 14
            }

            function PAYMASTER_RETURNED_INVALID_CONTEXT() -> ret {
                ret := 15
            }

            function PAYMASTER_RETURNED_CONTEXT_IS_TOO_LONG() -> ret {
                ret := 16
            }

            function ASSERTION_ERROR() -> ret {
                ret := 17
            }

            function FAILED_TO_MARK_FACTORY_DEPS() -> ret {
                ret := 18
            }

            function TX_VALIDATION_OUT_OF_GAS() -> ret {
                ret := 19
            }

            /// @dev Accepts a 1-word literal and returns its length in bytes
            /// @param str A string literal
            function getStrLen(str) -> len {
                len := 0
                // The string literals are stored left-aligned. Thus, 
                // In order to get the length of such string,
                // we shift it to the left (remove one byte to the left) until 
                // no more non-empty bytes are left.
                for {} str {str := shl(8, str)} {
                    len := add(len, 1)
                }
            }   

            // Selector of the errors used by the "require" statements in Solidity
            // and the one that can be parsed by our server.
            function GENERAL_ERROR_SELECTOR() -> ret {
                ret := {{REVERT_ERROR_SELECTOR}}
            }

            /// @notice Reverts with assertion error with the provided error string literal.
            function assertionError(err) {
                let ptr := 0

                // The first byte indicates that the revert reason is an assertion error
                mstore8(ptr, ASSERTION_ERROR())
                ptr := add(ptr, 1)

                // Then, we need to put the returndata in a way that is easily parsible by our 
                // servers
                mstore(ptr, GENERAL_ERROR_SELECTOR())
                ptr := add(ptr, 4)
                
                // Then, goes the "data offset". It is has constant value of 32.
                mstore(ptr, 32)
                ptr := add(ptr, 32)
                
                // Then, goes the length of the string:
                mstore(ptr, getStrLen(err))
                ptr := add(ptr, 32)
                
                // Then, we put the actual string
                mstore(ptr, err)
                ptr := add(ptr, 32)

                revert(0, ptr)
            }

            /// @notice Accepts an error code and whether there is a need to copy returndata
            /// @param errCode The code of the error
            /// @param sendReturnData A flag of whether or not the returndata should be used in the 
            /// revert reason as well. 
            function revertWithReason(errCode, sendReturnData) {
                let returndataLen := 1
                mstore8(0, errCode)

                if sendReturnData {
                    // Here we ignore all kinds of limits on the returned data,
                    // since the `revert` will happen shortly after.
                    returndataLen := add(returndataLen, returndatasize())
                    returndatacopy(1, 0, returndatasize())
                }
                revert(0, returndataLen)
            }

            function VM_HOOK_ACCOUNT_VALIDATION_ENTERED() -> ret {
                ret := 0
            }
            function VM_HOOK_PAYMASTER_VALIDATION_ENTERED() -> ret {
                ret := 1
            }
            function VM_HOOK_NO_VALIDATION_ENTERED() -> ret {
                ret := 2
            }
            function VM_HOOK_VALIDATION_STEP_ENDED() -> ret {
                ret := 3
            }
            function VM_HOOK_TX_HAS_ENDED() -> ret {
                ret := 4
            }
            function VM_HOOK_DEBUG_LOG() -> ret {
                ret := 5
            }
            function VM_HOOK_DEBUG_RETURNDATA() -> ret {
                ret := 6
            }
            function VM_HOOK_CATCH_NEAR_CALL() -> ret {
                ret := 7
            }

            /// @notice Triggers a VM hook. 
            /// The server will recognize it and output corresponding logs.
            function setHook(hook) {
                mstore(VM_HOOK_PTR(), hook)
            }   

            /// @notice Sets a value to a param of the vm hook.
            /// @param paramId The id of the VmHook parameter.
            /// @param value The value of the parameter.
            /// @dev This method should be called before trigger the VM hook itself.
            /// @dev It is the responsibility of the caller to never provide
            /// paramId smaller than the VM_HOOK_PARAMS()
            function storeVmHookParam(paramId, value) {
                let offset := add(VM_HOOK_PARAMS_OFFSET(), mul(32, paramId))
                mstore(offset, value)
            }
        }
    }
}
