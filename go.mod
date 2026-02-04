module bagpipe

go 1.17

require wangchucheng.com/hugo-eureka v0.9.3 // indirect

// Use GitHub when wangchucheng.com is unreachable (e.g. DNS or network issues)
replace wangchucheng.com/hugo-eureka => github.com/wangchucheng/hugo-eureka v0.9.3
