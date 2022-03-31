// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";

import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";

import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

contract RedirectAll is SuperAppBase {
    using CFAv1Library for CFAv1Library.InitData;

    // Initialize cfaV1 variable.
    CFAv1Library.InitData public cfaV1;

    ISuperfluid private _host;
    IConstantFlowAgreementV1 private _cfa; // The stored constant flow agreement class address.
    ISuperToken private _acceptedToken;
    address private _receiver;

    constructor(
        ISuperfluid host,
        ISuperToken acceptedToken,
        address receiver
    ) {
        assert(address(host) != address(0));
        assert(address(acceptedToken) != address(0));
        assert(address(receiver) != address(0));

        _host = host;
        _cfa = IConstantFlowAgreementV1(
            address(
                host.getAgreementClass(
                    keccak256(
                        "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
                    )
                )
            )
        );
        _acceptedToken = acceptedToken;
        _receiver = receiver;

        cfaV1 = CFAv1Library.InitData(_host, _cfa);

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

        _host.registerApp(configWord);
    }

    /**************************************************************************
     * Redirect Logic
     *************************************************************************/

    function currentReceiver()
        external
        view
        returns (
            uint256 startTime,
            address receiver,
            int96 flowRate
        )
    {
        if (_receiver != address(0)) {
            (startTime, flowRate, , ) = _cfa.getFlow(
                _acceptedToken,
                address(this),
                _receiver
            );
            receiver = _receiver;
        }
    }

    event ReceiverChanged(address receiver);

    function _updateOutflow(bytes calldata ctx)
        private
        returns (bytes memory newCtx)
    {
        newCtx = ctx;
        int96 netFlowRate = _cfa.getNetFlow(_acceptedToken, address(this));
        (, int96 outFlowRate, , ) = _cfa.getFlow(
            _acceptedToken,
            address(this),
            _receiver
        ); // TODO: Add check for non-existant flow.
        int96 inFlowRate = netFlowRate + outFlowRate;

        // @dev If inflowRate === 0, then delete existing flow.
        if (inFlowRate == int96(0)) {} else if (outFlowRate != int96(0)) {
            newCtx = cfaV1.updateFlowWithCtx(
                newCtx,
                _receiver,
                _acceptedToken,
                inFlowRate
            );
        }
    }

    // @dev Change the Receiver of the total flow.
    function _changeReceiver(address newReceiver) internal {
        require(newReceiver != address(0), "New receiver is zero address");
        // @dev Because our app is registered as final, we can't take downstream apps.
        require(
            !_host.isApp(ISuperApp(newReceiver)),
            "New receiver can not be a superApp"
        );

        if (newReceiver == _receiver) return;

        // @dev Delete flow to old receiver.
        (, int96 outFlowRate, , ) = _cfa.getFlow(
            _acceptedToken,
            address(this),
            _receiver
        ); // TODO: Add check for non-existant flow.
        if (outFlowRate > 0) {
            cfaV1.deleteFlow(address(this), _receiver, _acceptedToken);
            // @dev Create flow to new receiver.
            cfaV1.createFlow(
                newReceiver,
                _acceptedToken,
                _cfa.getNetFlow(_acceptedToken, address(this))
            );
        }
        // @dev Set global reciever to new receiver.
        _receiver = newReceiver;

        emit ReceiverChanged(_receiver);
    }

    /**************************************************************************
     * SuperApp callbacks
     *************************************************************************/

    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, /*_agreementId*/
        bytes calldata, /*_agreementData*/
        bytes calldata, /*_cbdata*/
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        return _updateOutflow(_ctx);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, /*_agreementId*/
        bytes calldata /*agreementData*/,
        bytes calldata, /*_cbdata*/
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        return _updateOutflow(_ctx);
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, /* _agreementId */
        bytes calldata, /* agreementData */
        bytes calldata, /* _cbdata */
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        // We should never revert in a termination callback.
        if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass))
            return _ctx;
        return _updateOutflow(_ctx);
    }

    function _isSameToken(ISuperToken superToken) private view returns (bool) {
        return address(superToken) == address(_acceptedToken);
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return
            ISuperAgreement(agreementClass).agreementType() == keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    }

    modifier onlyHost() {
        require(
            msg.sender == address(_host),
            "RedirectAll: suppoert only one host"
        );
        _;
    }

    modifier onlyExpected(ISuperToken superToken, address agreementClass) {
        require(_isSameToken(superToken), "RedirectAll: not accepted token");
        require(_isCFAv1(agreementClass), "RedirectAll: only CFAv1 supported");
        _;
    }
}
