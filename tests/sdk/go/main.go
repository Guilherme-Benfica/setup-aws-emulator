// Calls STS through the AWS SDK for Go v2 with no endpoint or credentials in code.
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sts"
)

func main() {
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	out, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	fmt.Println("account", *out.Account)
	if *out.Account != "000000000000" {
		os.Exit(1)
	}
}
