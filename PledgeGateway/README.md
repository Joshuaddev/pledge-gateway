# Pledge Gateway

A smart conditional payment system built with Clarity smart contracts that enables automated payments based on verifiable conditions, oracle data, and milestone achievements with built-in escrow protection.

## Overview

Pledge Gateway solves trust issues in conditional transactions by providing a decentralized escrow system where payments are automatically released only when predefined conditions are met and verified by trusted validators.

## Quick Start

### Create Conditional Payment
```clarity
;; Lock 5000 tokens until freelance project completion
(contract-call? .pledge-gateway create-conditional-pledge
  'SP-FREELANCER-ADDRESS u5000 "project-delivery" 
  0x1234abcd u4320 none) ;; 30-day deadline
```

### Verify Condition (Validator Only)
```clarity
;; Validator confirms project completion with 95% confidence
(contract-call? .pledge-gateway verify-condition 
  u1 0xverification-data u95)
```

### Execute Payment
```clarity
;; Release payment when conditions are met
(contract-call? .pledge-gateway execute-pledge u1)
```

### Add Project Milestone
```clarity
;; Break project into trackable milestones
(contract-call? .pledge-gateway add-milestone u1 u1 
  "Complete UI mockups" u2000)
```

## Core Features

- **Conditional Escrow**: Funds locked until conditions are verified
- **Validator Network**: Trusted entities verify condition fulfillment  
- **Oracle Integration**: External data feeds for automated verification
- **Milestone Tracking**: Break complex projects into measurable steps
- **Automatic Execution**: Payments release when conditions are met
- **Deadline Protection**: Automatic refunds for failed conditions
- **Reputation System**: Track user success rates and reliability

## Condition Types

| Type | Description | Use Case |
|------|-------------|----------|
| `project-delivery` | Work completion verification | Freelance projects |
| `sales-target` | Performance goal achievement | Sales commissions |
| `oracle-price` | Market price conditions | Trading/betting |
| `time-release` | Date-based releases | Vesting schedules |
| `multi-approval` | Multiple party sign-off | Complex agreements |

## Use Cases

### Freelance Escrow
```clarity
;; Pay developer when project is complete
(contract-call? .pledge-gateway create-conditional-pledge
  developer-address u10000 "project-delivery" project-specs u8640 none)
```

### Sales Commission
```clarity
;; Commission paid when sales target reached
(contract-call? .pledge-gateway create-conditional-pledge
  sales-rep u5000 "sales-target" target-data u2160 (some oracle-address))
```

### Insurance Claims
```clarity
;; Automatic payout based on weather data
(contract-call? .pledge-gateway create-conditional-pledge
  policy-holder u50000 "weather-event" event-criteria u720 (some weather-oracle))
```

### Crowdfunding
```clarity
;; Release funds when funding goal met
(contract-call? .pledge-gateway create-conditional-pledge
  project-creator u100000 "funding-goal" goal-data u17280 none)
```

## Security Features

- **Validator Authorization**: Only registered validators can verify conditions
- **Confidence Threshold**: 80% confidence required for condition verification
- **Deadline Enforcement**: Automatic expiration prevents indefinite locks
- **Escrow Protection**: Funds secured until conditions are satisfied
- **Reputation Tracking**: Monitor user reliability and success rates
- **Platform Fees**: 2% fee structure prevents spam and funds development

## Workflow

1. **Create Pledge**: Payer locks funds with specific conditions
2. **Add Milestones**: Break complex conditions into steps (optional)
3. **Condition Verification**: Validators confirm condition fulfillment
4. **Automatic Execution**: Payment releases when verified
5. **Refund Protection**: Failed conditions trigger automatic refunds

## Error Codes

- `u401` - Unauthorized access
- `u404` - Pledge not found
- `u400` - Invalid input data
- `u402` - Insufficient funds
- `u403` - Condition not met
- `u405` - Pledge expired
- `u406` - Already executed
- `u407` - Oracle verification failed

## Functions Reference

| Function | Access | Description |
|----------|--------|-------------|
| `create-conditional-pledge` | Public | Lock funds behind conditions |
| `verify-condition` | Validators | Confirm condition fulfillment |
| `execute-pledge` | Public | Release payment when verified |
| `refund-expired-pledge` | Public | Refund failed conditions |
| `add-milestone` | Creator | Add progress tracking |
| `register-condition-validator` | Owner | Authorize validators |

## Integration Examples

Smart contract integration:
```clarity
(define-public (create-escrow-payment (recipient principal) (amount uint))
  (contract-call? .pledge-gateway create-conditional-pledge
    recipient amount "service-delivery" 
    (unwrap! (get-service-specs) (err u1)) 
    u4320 none))
```

Check payment eligibility:
```clarity
(define-read-only (can-claim-payment (pledge-id uint))
  (let ((eligibility (unwrap! (contract-call? .pledge-gateway check-pledge-eligibility pledge-id) false)))
    (get can-execute eligibility)))
```

## Best Practices

### For Payers
- Set realistic deadlines for condition verification
- Use clear, measurable conditions
- Choose reputable validators
- Consider milestone-based payments for complex projects

### For Recipients
- Understand condition requirements before accepting
- Provide clear deliverables that match conditions
- Communicate progress regularly
- Maintain good reputation scores

### For Validators
- Verify conditions objectively and accurately
- Maintain high confidence scores
- Respond to verification requests promptly
- Build reputation through consistent validation