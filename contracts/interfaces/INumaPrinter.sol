// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaPrinter {
  
    function getSynthScalingUpdate(
    ) external returns (uint256,uint256,uint256);
}
