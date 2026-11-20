package economy

import (
	"errors"
	"math/big"
	"strings"
)

var ErrInvalidExchangeRate = errors.New("invalid exchange rate")

// CalculateExchangeAmount applies an integer rational rate, then deducts a
// basis-point fee. Both conversion and fee rounding are deterministic:
// converted amount rounds down; a non-zero fee rounds up.
func CalculateExchangeAmount(fromAmount, numerator, denominator int64, feeBP int) (gross, fee, net int64, err error) {
	if fromAmount <= 0 || numerator <= 0 || denominator <= 0 || feeBP < 0 || feeBP > 3000 {
		return 0, 0, 0, ErrInvalidExchangeRate
	}
	n := new(big.Int).Mul(big.NewInt(fromAmount), big.NewInt(numerator))
	n.Quo(n, big.NewInt(denominator))
	if !n.IsInt64() || n.Sign() <= 0 {
		return 0, 0, 0, ErrInvalidExchangeRate
	}
	gross = n.Int64()
	if feeBP == 0 {
		return gross, 0, gross, nil
	}
	feeBig := new(big.Int).Mul(big.NewInt(gross), big.NewInt(int64(feeBP)))
	feeBig.Add(feeBig, big.NewInt(9999))
	feeBig.Quo(feeBig, big.NewInt(10000))
	if !feeBig.IsInt64() || feeBig.Int64() >= gross {
		return 0, 0, 0, ErrInvalidExchangeRate
	}
	fee = feeBig.Int64()
	return gross, fee, gross - fee, nil
}

type CultivationAffinity struct {
	TargetTag string
	EfficiencyBP int
}

// ResolveCultivationEfficiency chooses the most specific matching tag.
// If multiple equally specific tags match, the highest efficiency wins.
// Fiat currencies and non-cultivation assets always return zero.
func ResolveCultivationEfficiency(currencyClass string, cultivationUsable bool, affinities []CultivationAffinity, targetTags []string) int {
	if currencyClass != "cultivation" || !cultivationUsable {
		return 0
	}
	bestSpecificity, bestEfficiency := -1, 0
	for _, affinity := range affinities {
		tag := strings.TrimSpace(affinity.TargetTag)
		if tag == "" || affinity.EfficiencyBP < 0 || affinity.EfficiencyBP > 20000 {
			continue
		}
		if tag == "all" {
			if bestSpecificity < 0 && affinity.EfficiencyBP > bestEfficiency {
				bestEfficiency = affinity.EfficiencyBP
			}
			continue
		}
		for _, target := range targetTags {
			if strings.TrimSpace(target) != tag {
				continue
			}
			specificity := strings.Count(tag, ":") + 1
			if specificity > bestSpecificity || (specificity == bestSpecificity && affinity.EfficiencyBP > bestEfficiency) {
				bestSpecificity, bestEfficiency = specificity, affinity.EfficiencyBP
			}
		}
	}
	return bestEfficiency
}
